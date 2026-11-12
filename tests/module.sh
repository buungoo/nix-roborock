cp "$renderer" bootstrap.py
mkdir tests
cp "$testFile" tests/test_bootstrap.py
export HOME="$TMPDIR"
python -m pytest -q tests
touch "$out"
