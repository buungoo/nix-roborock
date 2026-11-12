cp -r "$sourceTree" source
chmod -R u+w source
cd source
export HOME="$TMPDIR"
python -m pytest -q
touch "$out"
