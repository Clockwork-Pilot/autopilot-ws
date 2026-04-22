#!/bin/bash

# write to file ~/.bashrc
cat >> ~/.bashrc << 'EOF'
source ~/venv/bin/activate
EOF

source ~/venv/bin/activate

mkdir -p ~/.local

# export plugin paths
export PATH="$(python -c "import sys; sys.path.insert(0, '$CLAUDE_PLUGIN_ROOT'); from config import PATH; print(PATH)"):$PATH"
