#!/bin/bash

# -----------------------------------------------------------------------------
# AI-powered Git Commit Function
# This function provides an interactive way to generate and manage Git commit messages using AI.
# Usage: gcm_ai
# Requirements: llm CLI utility (https://llm.datasette.io/en/stable/)

gcm_ai() {
    # Function to generate commit message
    generate_commit_message() {
        git diff --cached | llm -m llama3.2:3b "

Below is a diff of all staged changes:
\`\`\`
git diff --cached
\`\`\`
Based on the following staged changes from the git diff --cached, please generate a commit message that summarizes the changes in approximately 10 words. The message should be concise and clearly reflect the modifications made.

Only the commit message should be returned, with no additional context or explanations.

Write just the commit message, now."

    }

    # Function to read user input compatibly with both Bash and Zsh
    read_input() {
        if [ -n "$ZSH_VERSION" ]; then
            echo -n "$1"
            read -r REPLY
        else
            read -p "$1" -r REPLY
        fi
    }

    # Main script
    echo "Generating AI-powered commit message..."
    commit_message=$(generate_commit_message)

    while true; do
        echo -e "\nProposed commit message:"
        echo "$commit_message"

        read_input "Do you want to (a)ccept, (e)dit, (r)egenerate, or (c)ancel? "
        choice=$REPLY

        case "$choice" in
            a|A )
                if git commit -m "$commit_message"; then
                    echo "Changes committed successfully!"
                    return 0
                else
                    echo "Commit failed. Please check your changes and try again."
                    return 1
                fi
                ;;
            e|E )
                read_input "Enter your commit message: "
                commit_message=$REPLY
                if [ -n "$commit_message" ] && git commit -m "$commit_message"; then
                    echo "Changes committed successfully with your message!"
                    return 0
                else
                    echo "Commit failed. Please check your message and try again."
                    return 1
                fi
                ;;
            r|R )
                echo "Regenerating commit message..."
                commit_message=$(generate_commit_message)
                ;;
            c|C )
                echo "Commit cancelled."
                return 1
                ;;
            * )
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
}
