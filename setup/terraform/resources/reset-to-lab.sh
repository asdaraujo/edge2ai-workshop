TARGET_LAB=${1:-99}

echo "Executing global teardown"
python3 -c "import utils; utils.global_teardown()"
echo "Running all setup functions less than Lab ${TARGET_LAB}"
python3 -c "import utils; utils.global_setup(target_lab=${TARGET_LAB})"
echo "Done"