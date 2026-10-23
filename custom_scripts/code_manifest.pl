#!/usr/bin/env perl
###############################################################################
# code_manifest.pl — byte-level manifest of a code tree, identical on any OS
#
#   code_manifest.pl ROOT [--exclude-from FILE | --exclude-b64 B64] [--exclude-default]
#                         [--git | --git-only]
#   ssh host "perl - Code --exclude-b64 <b64> --git" < code_manifest.pl   # nothing copied
#
# stdout, one line per entry, 6 space-separated fields, sorted bytewise on the path:
#   f MODE SIZE SHA256 -      path        regular file
#   d MODE -    -      -      path        directory (empty dirs listed too)
#   l -    -    -      TARGET path        symlink (perms ignored: rsync does not keep them)
#   o MODE -    -      -      path        anything else (fifo, socket, device)
# Paths are NFC-normalised UTF-8; "\" -> "\\", bytes <= 0x20, 0x7f and invalid
# UTF-8 bytes >= 0x80 -> \xHH. With --git, after the file lines, per repo:
#   G REPO HEAD   ref: refs/heads/x | SHA        G REPO REF   refs/... SHA   (no refs/remotes)
#   G REPO STASH  N SHA                          G REPO INDEX N SHA256(git ls-files -s)
#   G REPO STATUS N SHA256(porcelain status, excluded paths removed)
# Git runs with --no-optional-locks, GIT_OPTIONAL_LOCKS=0, GIT_CONFIG_NOSYSTEM=1,
# GIT_CONFIG_GLOBAL=/dev/null, LC_ALL=C: it never writes to a repo. --git-only
# skips the file lines (fast fingerprint).
#
# Excludes use rsync rules: "/a/b/" anchored to ROOT, trailing "/" = dirs only,
# bare name = any component, "*" "?" "[..]" stay inside one component, "**" crosses
# "/", "- " prefix accepted, "#" and ";" comments. --exclude-default is the fixed
# list of ~/.migration/code-excl.txt. Always skipped: .git/index, .git/FETCH_HEAD,
# .git/worktrees/*/{index,gitdir}, .git/refs/remotes/, .git/logs/refs/remotes/.
# Normalised before hashing: a worktree ".git" FILE loses the absolute prefix up to
# "/<basename ROOT>/" (git worktree repair rewrites it), ".git/config" loses its
# "ignorecase =" line (MIGRATE.md step 9 flips it on Linux).
#
# stderr: "CASE-COLLISION path" (two paths equal when lower-cased/NFC) and a final
# "ERRORS n" (unreadable dirs, failed stat/read/readlink, failed git commands).
# Exit 0 = no errors, 1 = errors, 2 = usage. Core Perl only (5.30 mac, 5.36 Linux).
###############################################################################
use strict;
use warnings;
use File::Find;
use Digest::SHA;
use Unicode::Normalize;
use Encode qw(decode encode FB_CROAK LEAVE_SRC);
use MIME::Base64;

my @DEFAULT_EXCL = qw(/000-config/001-dotfiles/ /000-config/dotfiles-uv-worktree/
  .venv venv .venv-* node_modules .next __pycache__ .pytest_cache .mypy_cache
  .terraform .DS_Store ._*);

sub usage { print STDERR "usage: code_manifest.pl ROOT [--exclude-from FILE | --exclude-b64 B64] [--exclude-default] [--git | --git-only]\n"; exit 2 }

my ($root, @pat, $do_git, $git_only);
while (@ARGV) {
  my $a = shift @ARGV;
  if    ($a eq '--exclude-from')    { my $f = shift(@ARGV) // usage(); open(my $fh, '<', $f) or do { print STDERR "cannot read $f: $!\n"; exit 2 }; push @pat, <$fh>; close $fh }
  elsif ($a eq '--exclude-b64')     { my $b = shift(@ARGV) // usage(); push @pat, split /\n/, decode_base64($b) }
  elsif ($a eq '--exclude-default') { push @pat, @DEFAULT_EXCL }
  elsif ($a eq '--git')             { $do_git = 1 }
  elsif ($a eq '--git-only')        { $do_git = 1; $git_only = 1 }
  elsif ($a =~ /^-/)                { usage() }
  elsif (!defined $root)            { $root = $a }
  else                              { usage() }
}
usage() unless defined $root;
chdir $root or do { print STDERR "cannot chdir to $root: $!\n"; exit 2 };
(my $rootbase = $root) =~ s{/+$}{};
$rootbase =~ s{^.*/}{};
$rootbase = '.' if $rootbase eq '';

# ---------------------------------------------------------------- exclude rules
my @rules;
sub glob2re {
  my $g  = shift;
  my $re = '';
  while ($g =~ /\G(\*\*|\*|\?|\[[^\]]*\]|\\.|[^*?\[\\]+)/gc) {
    my $t = $1;
    if    ($t eq '**')     { $re .= '.*' }
    elsif ($t eq '*')      { $re .= '[^/]*' }
    elsif ($t eq '?')      { $re .= '[^/]' }
    elsif ($t =~ /^\[/)    { (my $c = $t) =~ s/^\[!/[^/; $re .= $c }
    elsif ($t =~ /^\\(.)/) { $re .= quotemeta($1) }
    else                   { $re .= quotemeta($t) }
  }
  my $rest = substr($g, pos($g) // 0);
  $re .= quotemeta($rest) if length $rest;
  return $re;
}
for my $raw (@pat) {
  my $p = $raw;
  $p =~ s/\r?\n$//;
  $p =~ s/^\s+|\s+$//g;
  next if $p eq '' or $p =~ /^[#;]/;
  if ($p =~ /^\+\s/) { print STDERR "include rules (+) are not supported: $raw\n"; exit 2 }
  $p =~ s/^-\s+//;
  $p = NFC(eval { decode('UTF-8', $p, FB_CROAK | LEAVE_SRC) } // $p);
  my %r = (anchored => 0, dironly => 0, slash => 0);
  $r{anchored} = 1 if $p =~ s{^/+}{};
  $r{dironly}  = 1 if $p =~ s{/+$}{};
  next if $p eq '';
  $r{slash} = 1 if $p =~ m{/};
  my $re = glob2re($p);
  $r{re} = $r{anchored} ? qr/^$re$/ : $r{slash} ? qr/(?:^|\/)$re$/ : qr/^$re$/;
  push @rules, \%r;
}
# $path: NFC, no leading/trailing slash. Parents are assumed already checked (pruned).
sub excluded {
  my ($path, $isdir) = @_;
  my $base = $path =~ m{([^/]+)$} ? $1 : $path;
  for my $r (@rules) {
    next if $r->{dironly} && !$isdir;
    if ($r->{anchored} || $r->{slash}) { return 1 if $path =~ $r->{re} }
    else                               { return 1 if $base =~ $r->{re} }
  }
  return 0;
}
# same, but also checks every ancestor directory (for git status entries)
sub excluded_deep {
  my ($path, $isdir) = @_;
  my @c = split m{/}, $path;
  for my $i (0 .. $#c - 1) { return 1 if excluded(join('/', @c[0 .. $i]), 1) }
  return excluded($path, $isdir);
}
sub git_internal_skip {
  return $_[0] =~ m{(?:^|/)\.git/(?:index|FETCH_HEAD|worktrees/[^/]+/(?:index|gitdir)|refs/remotes(?:/|$)|logs/refs/remotes(?:/|$))$};
}

# ---------------------------------------------------------------- helpers
my $err = 0;
sub oops { $err++; print STDERR "ERROR $_[0]\n" }
local $SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/\s+$//; oops($m) };   # File::Find opendir failures etc.

sub nfc_bytes {    # raw bytes -> NFC UTF-8 bytes (invalid UTF-8 kept raw)
  my $raw = shift;
  my $u = eval { decode('UTF-8', $raw, FB_CROAK | LEAVE_SRC) };
  return defined $u ? encode('UTF-8', NFC($u)) : $raw;
}
sub esc {          # escape for the manifest line (input: bytes; set $raw when invalid UTF-8)
  my ($b, $invalid) = @_;
  $b =~ s/\\/\\\\/g;
  $b =~ s/([\x00-\x20\x7f])/sprintf('\\x%02x', ord $1)/ge;
  $b =~ s/([\x80-\xff])/sprintf('\\x%02x', ord $1)/ge if $invalid;
  return $b;
}
sub enc_path {     # raw path bytes -> (escaped NFC path, NFC path for matching)
  my $raw = shift;
  my $u = eval { decode('UTF-8', $raw, FB_CROAK | LEAVE_SRC) };
  if (defined $u) { my $b = encode('UTF-8', NFC($u)); return (esc($b, 0), $b) }
  return (esc($raw, 1), $raw);
}
sub sha_file {
  my $f = shift;
  my $h = eval { Digest::SHA->new(256)->addfile($f, 'b')->hexdigest };
  defined $h or do { oops("read $f: " . ($@ || $!)) };
  return $h;
}
sub sha_str { return Digest::SHA::sha256_hex($_[0]) }
# "gitdir: /abs/.../<ROOT basename>/x/.git/worktrees/n" -> "gitdir: x/.git/worktrees/n"; when the
# root is mounted under another name, keep the longest suffix that exists under ROOT.
sub norm_gitdir {
  my $c = shift;
  return $c if $c =~ s{^(gitdir:[ \t]*)/.*?/\Q$rootbase\E/}{$1}m;
  if ($c =~ /^gitdir:[ \t]*(\/[^\r\n]*)/m) {
    my $abs = $1;
    my @parts = grep { length } split m{/}, $abs;
    for my $i (0 .. $#parts) {
      my $suf = join('/', @parts[$i .. $#parts]);
      if (-e "./$suf") { $c =~ s{^(gitdir:[ \t]*)\Q$abs\E}{$1$suf}m; last }
    }
  }
  return $c;
}

# ---------------------------------------------------------------- walk
my (@o, @repos);
find({ no_chdir => 1, wanted => sub {
  my $p = $File::Find::name;
  $p =~ s{^\./?}{};
  return if $p eq '';
  my @st = lstat($_);
  if (!@st) { oops("lstat $p: $!"); return }
  my $isdir  = -d _ && !-l _;
  my ($ep, $np) = enc_path($p);
  my $base = $np =~ m{([^/]+)$} ? $1 : $np;
  if (excluded($np, $isdir)) { $File::Find::prune = 1 if $isdir; return }
  if (git_internal_skip($np)) { $File::Find::prune = 1 if $isdir; return }
  if ($base eq '.git') {
    (my $repo = $p) =~ s{/?\.git$}{};
    $repo = '.' if $repo eq '';
    push @repos, $repo;
    if ($git_only) { $File::Find::prune = 1 if $isdir; return }
  }
  return if $git_only;
  my $mode = sprintf '%04o', $st[2] & 07777;
  if (-l _) {
    my $t = readlink($_);
    if (!defined $t) { oops("readlink $p: $!"); return }
    my $u = eval { decode('UTF-8', $t, FB_CROAK | LEAVE_SRC) };
    push @o, [$np, "l - - - " . esc($t, !defined $u) . " $ep", $p];
  }
  elsif ($isdir) { push @o, [$np, "d $mode - - - $ep", $p] }
  elsif (-f _) {
    my ($size, $h) = ($st[7]);
    if ($base eq '.git') {                                 # worktree pointer: drop the absolute prefix
      if (open(my $fh, '<', $_)) { local $/; my $c = <$fh>; close $fh;
        $c = norm_gitdir($c); $size = length $c; $h = sha_str($c) }
      else { oops("read $p: $!"); return }
    }
    elsif ($np =~ m{(?:^|/)\.git/config$}) {               # ignorecase is flipped on Linux (step 9)
      if (open(my $fh, '<', $_)) { local $/; my $c = <$fh>; close $fh;
        $c =~ s/^[ \t]*ignorecase[ \t]*=.*\n?//mg; $size = length $c; $h = sha_str($c) }
      else { oops("read $p: $!"); return }
    }
    else { $h = sha_file($_) // 'ERR' }
    push @o, [$np, "f $mode $size $h - $ep", $p];
  }
  else { push @o, [$np, "o $mode - - - $ep", $p] }
}}, '.');

# ---------------------------------------------------------------- git layer
my @g;
if ($do_git) {
  for my $k (qw(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE)) { delete $ENV{$k} }
  $ENV{GIT_OPTIONAL_LOCKS}  = '0';
  $ENV{GIT_CONFIG_NOSYSTEM} = '1';
  $ENV{GIT_CONFIG_GLOBAL}   = '/dev/null';
  $ENV{GIT_TERMINAL_PROMPT} = '0';
  $ENV{LC_ALL}              = 'C';
  # run git without a shell, stderr merged; returns (rc, output) — undef rc if git is missing
  my $git = sub {
    my ($repo, @a) = @_;
    my @cmd = ('git', '-C', "./$repo", '--no-optional-locks', '-c', 'safe.directory=*', '-c', 'core.fsmonitor=false', @a);
    my $pid = open(my $fh, '-|');
    if (!defined $pid) { oops("fork: $!"); return (undef, '') }
    if ($pid == 0) { open(STDERR, '>&', \*STDOUT); open(STDIN, '<', '/dev/null'); exec { $cmd[0] } @cmd or exit 127 }
    local $/; my $out = <$fh>; close $fh;
    my $rc = $? == -1 ? 127 : $? >> 8;
    return ($rc, $out // '');
  };
  for my $repo (sort @repos) {
    my ($er, $nr) = enc_path($repo);
    my $tag = "G $er";
    my ($rc, $out);
    ($rc, $out) = $git->($repo, 'symbolic-ref', '-q', 'HEAD');
    if ($rc == 127) { oops("git not found ($repo)"); last }
    if ($rc == 0 && $out =~ /^(\S+)/) { push @g, "$tag HEAD ref: $1" }
    else {
      ($rc, $out) = $git->($repo, 'rev-parse', '--verify', '-q', 'HEAD');
      if ($rc == 0 && $out =~ /^([0-9a-f]+)/) { push @g, "$tag HEAD $1" }
      else { oops("git HEAD $repo: " . ($out =~ /^(.*)$/m ? $1 : "rc=$rc")); next }
    }
    ($rc, $out) = $git->($repo, 'for-each-ref', '--format=%(refname) %(objectname)');
    if ($rc) { oops("git for-each-ref $repo: rc=$rc") } else {
      for my $l (split /\n/, $out) { next if $l =~ m{^refs/remotes/}; next if $l eq ''; my ($n, $s) = split / /, $l, 2; push @g, "$tag REF " . esc(nfc_bytes($n), 0) . " $s" }
    }
    ($rc, $out) = $git->($repo, 'stash', 'list', '--format=%H');
    if ($rc) { oops("git stash list $repo: rc=$rc") } else {
      my $i = 0; push @g, "$tag STASH " . $i++ . " $_" for grep { /^[0-9a-f]+$/ } split /\n/, $out;
    }
    ($rc, $out) = $git->($repo, 'ls-files', '-s', '-z');
    if ($rc) { oops("git ls-files $repo: rc=$rc") } else {
      my @e = split /\0/, $out; push @g, "$tag INDEX " . scalar(@e) . " " . sha_str(join("\0", map { nfc_bytes($_) } @e));
    }
    ($rc, $out) = $git->($repo, 'status', '--porcelain=v1', '-z', '--untracked-files=normal');
    if ($rc) { oops("git status $repo: " . ($out =~ /^(.*)$/m ? $1 : "rc=$rc")) } else {
      my @rec = split /\0/, $out; my @keep;
      while (@rec) {
        my $r = shift @rec; next if $r eq '';
        my ($xy, $path) = (substr($r, 0, 2), substr($r, 3));
        my $orig = ($xy =~ /^[RC]/ || $xy =~ /^.[RC]/) ? shift(@rec) : undef;
        my $isdir = $path =~ s{/$}{} ? 1 : 0;
        my $full = $repo eq '.' ? $path : "$repo/$path";
        next if excluded_deep(nfc_bytes($full), $isdir);
        my $line = $xy . ' ' . nfc_bytes($path) . ($isdir ? '/' : '');
        $line .= "\0" . nfc_bytes($orig) if defined $orig;
        push @keep, $line;
      }
      @keep = sort @keep;
      push @g, "$tag STATUS " . scalar(@keep) . " " . sha_str(join("\0", @keep));
    }
  }
}

# ---------------------------------------------------------------- output
binmode STDOUT, ':raw';
for my $e (sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @o) { print $e->[1], "\n" }
print "$_\n" for sort @g;
my %lc;
$lc{lc $_->[0]}{$_->[2]} = 1 for @o;   # inner key = raw bytes: NFD vs NFC twins collide too
for my $k (sort keys %lc) {
  next if keys %{$lc{$k}} < 2;
  print STDERR "CASE-COLLISION " . esc($_, 0) . "\n" for sort keys %{$lc{$k}};
}
print STDERR "ERRORS $err\n";
exit($err ? 1 : 0);
