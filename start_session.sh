#!/bin/bash
# Launch the f5xc-salesdemos team lead and auto-send the team creation prompt

SESSION="f5xc-salesdemoss"
VAULTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null

# Start tmux with claude
tmux new-session -d -s "$SESSION" -n lead -c "$VAULTS_DIR"
tmux send-keys -t "$SESSION:lead" "claude --dangerously-skip-permissions" Enter

# Wait for claude to initialize, then send the team creation prompt
sleep 3
tmux send-keys -t "$SESSION:lead" "Create the agent team with life, work, and customers teammates" Enter

tmux attach-session -t "$SESSION"
