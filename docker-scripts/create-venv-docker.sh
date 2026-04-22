set -e

# called from user-entrypoint.sh script (from inside of docker)
python3 -m venv ~/venv &&
source ~/venv/bin/activate &&
pip install -r "$CLAUDE_PLUGIN_ROOT/knowledge_tool/requirements.txt" &&
pip install -r "$CLAUDE_PLUGIN_ROOT/requirements.txt"
pip install yq==3.4.3
