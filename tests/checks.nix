{
  pkgs,
  testEnv,
  upstream,
  bootstrap,
}: {
  upstream = pkgs.runCommand "roborock-local-server-tests" {
    nativeBuildInputs = [testEnv pkgs.mosquitto];
    sourceTree = upstream;
  } (builtins.readFile ./upstream.sh);
  module = pkgs.runCommand "roborock-local-server-bootstrap-tests" {
    nativeBuildInputs = [testEnv];
    renderer = bootstrap;
    testFile = ./test_bootstrap.py;
  } (builtins.readFile ./module.sh);
}
