# #!/bin/bash

# # -----------------------------------------------------------------------------
# # AI-powered Git Commit Function
# # This function provides an interactive way to generate and manage Git commit messages using AI.
# # Usage: gcm_ai
# # Requirements: llm CLI utility (https://llm.datasette.io/en/stable/)

# gcm_ai() {
#     # Function to generate commit message
#     generate_commit_message() {
#         git diff --cached | llm -m llama3.2:3b "

# Below is a diff of all staged changes:
# \`\`\`
# git diff --cached
# \`\`\`
# Based on the following staged changes from the git diff --cached, please generate a commit message that summarizes the changes in approximately 10 words. The message should be concise and clearly reflect the modifications made.

# Only the commit message should be returned, with no additional context or explanations.

# Write just the commit message, now."

#     }

#     # Function to read user input compatibly with both Bash and Zsh
#     read_input() {
#         if [ -n "$ZSH_VERSION" ]; then
#             echo -n "$1"
#             read -r REPLY
#         else
#             read -p "$1" -r REPLY
#         fi
#     }

#     # Main script
#     echo "Generating AI-powered commit message..."
#     commit_message=$(generate_commit_message)

#     while true; do
#         echo -e "\nProposed commit message:"
#         echo "$commit_message"

#         read_input "Do you want to (a)ccept, (e)dit, (r)egenerate, or (c)ancel? "
#         choice=$REPLY

#         case "$choice" in
#             a|A )
#                 if git commit -m "$commit_message"; then
#                     echo "Changes committed successfully!"
#                     return 0
#                 else
#                     echo "Commit failed. Please check your changes and try again."
#                     return 1
#                 fi
#                 ;;
#             e|E )
#                 read_input "Enter your commit message: "
#                 commit_message=$REPLY
#                 if [ -n "$commit_message" ] && git commit -m "$commit_message"; then
#                     echo "Changes committed successfully with your message!"
#                     return 0
#                 else
#                     echo "Commit failed. Please check your message and try again."
#                     return 1
#                 fi
#                 ;;
#             r|R )
#                 echo "Regenerating commit message..."
#                 commit_message=$(generate_commit_message)
#                 ;;
#             c|C )
#                 echo "Commit cancelled."
#                 return 1
#                 ;;
#             * )
#                 echo "Invalid choice. Please try again."
#                 ;;
#         esac
#     done
# }


#!/bin/zsh

###############################################################################
# 🤖 gcm_ai — AI-powered Git Commit
#
# Usage:
#   gcm_ai                     # default model
#   gcm_ai --model gpt-4o      # override model
#   gcm_ai --conventional      # enforce conventional commits format
#
# Requirements:
#   llm CLI → https://llm.datasette.io/en/stable/
#   Install: pip install llm
###############################################################################

gcm_ai() {

  ###############################################################################
  # Config
  ###############################################################################
  local DEFAULT_MODEL="gpt-4o-mini"
  local model="$DEFAULT_MODEL"
  local conventional=false

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)     model="$2"; shift 2 ;;
      --conventional) conventional=true; shift ;;
      *) echo "⚠️  Unknown option: $1"; return 1 ;;
    esac
  done

  ###############################################################################
  # Guards
  ###############################################################################

  # Check llm is installed
  if ! command -v llm &>/dev/null; then
    echo "❌ 'llm' CLI not found."
    echo "   Install it with: pip install llm"
    echo "   Docs: https://llm.datasette.io/en/stable/"
    return 1
  fi

  # Must be inside a git repo
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "❌ Not inside a git repository."
    return 1
  fi

  # Must have staged changes
  if git diff --cached --quiet; then
    echo "⚠️  No staged changes found."
    echo "   Stage your changes first with: git add <files>"
    return 1
  fi

  ###############################################################################
  # Helpers
  ###############################################################################

  # Spinner while waiting for model
  _spinner() {
    local pid=$1
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r  %s  Thinking..." "${frames[$((i % ${#frames[@]}))]}"
      i=$((i + 1))
      sleep 0.1
    done
    printf "\r                        \r"
  }

  # Generate commit message via llm
  _generate() {
    local diff
    diff=$(git diff --cached)

    local prompt
    if [ "$conventional" = true ]; then
      prompt="You are a git commit message generator. Given the diff below, write a conventional commit message.

Format: <type>(<scope>): <short description>
Types: feat, fix, chore, docs, style, refactor, test, perf
Rules:
- type and scope lowercase
- description under 72 chars, imperative tense
- no period at end
- return ONLY the commit message, nothing else

Diff:
${diff}"
    else
      prompt="You are a git commit message generator. Given the diff below, write a concise git commit message.

Rules:
- under 72 characters
- imperative tense (e.g. 'Add feature' not 'Added feature')
- no period at end
- return ONLY the commit message, nothing else

Diff:
${diff}"
    fi

    llm -m "$model" "$prompt" 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  }

  # Show staged files summary
  _show_staged() {
    echo ""
    echo "  📂 Staged files:"
    git diff --cached --stat | head -10 | sed 's/^/     /'
    echo ""
  }

  # Read user input (zsh/bash compatible)
  _read_input() {
    echo -n "$1"
    read -r REPLY
  }

  ###############################################################################
  # Main loop
  ###############################################################################
  _show_staged

  echo "  🤖 Model: $model$([ "$conventional" = true ] && echo ' · conventional commits')"
  echo ""

  # Generate first message with spinner
  echo -n "  ⠋  Thinking..."
  commit_message=$(_generate) &
  local gen_pid=$!
  _spinner $gen_pid
  wait $gen_pid

  if [ -z "$commit_message" ]; then
    echo "❌ Failed to generate commit message. Check your llm setup."
    echo "   Try: llm models list"
    return 1
  fi

  while true; do
    echo "  💬 Proposed message:"
    echo ""
    echo "     $commit_message"
    echo ""
    _read_input "  (a)ccept  (e)dit  (r)egenerate  (p)ush after  (c)ancel → "
    local choice=$REPLY

    case "$choice" in
      a|A)
        if git commit -m "$commit_message"; then
          echo ""
          echo "  ✅ Committed!"
        else
          echo "  ❌ Commit failed."
          return 1
        fi
        return 0
        ;;

      p|P)
        if git commit -m "$commit_message"; then
          echo ""
          echo "  ✅ Committed! Pushing..."
          git push && echo "  🚀 Pushed!" || echo "  ⚠️  Push failed — check your remote."
        else
          echo "  ❌ Commit failed."
          return 1
        fi
        return 0
        ;;

      e|E)
        _read_input "  ✏️  Your message: "
        commit_message=$REPLY
        if [ -z "$commit_message" ]; then
          echo "  ⚠️  Empty message, try again."
          continue
        fi
        if git commit -m "$commit_message"; then
          echo ""
          echo "  ✅ Committed with your message!"
        else
          echo "  ❌ Commit failed."
          return 1
        fi
        return 0
        ;;

      r|R)
        echo ""
        echo -n "  ⠋  Regenerating..."
        commit_message=$(_generate) &
        local regen_pid=$!
        _spinner $regen_pid
        wait $regen_pid
        ;;

      c|C)
        echo "  ↩️  Cancelled."
        return 1
        ;;

      *)
        echo "  ⚠️  Invalid choice."
        ;;
    esac
  done
}