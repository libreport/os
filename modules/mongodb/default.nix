{ config, pkgs, lib, ... }:
let
  cfg = config.services.mongodb or {};
  mongoInit = pkgs.writeText "mongo-init.js" (builtins.readFile ./mongo-init.js);
in
{
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {
    # MongoDB container (matches compose.yaml)
    mongo = {
      image = "mongo:7.0.23";
      environment = {
        MONGO_INITDB_ROOT_USERNAME = "root";
        MONGO_INITDB_ROOT_PASSWORD = "supersecret";
        MONGO_INITDB_DATABASE = "telegram_bot";
      };
      # ports = [ "27017:27017" ];
      # Fixed host path for persistent data and init script mount
      volumes = [
        "/opt/mongodb/data:/data/db"
        "${mongoInit}:/docker-entrypoint-initdb.d/mongo-init.js:ro"
      ];
      # initialize scripts can be mounted from the repo by the caller
      autoStart = true;
      cmd = ["mongod" "--auth"];
    };

    # Mongo Express admin UI (matches compose.yaml)
    mongo-express = {
      image = "mongo-express:1.0.2-20-alpine3.19";
      ports = [ "8081:8081" ];
      environment = {
        ME_CONFIG_MONGODB_ADMINUSERNAME = "root";
        ME_CONFIG_MONGODB_ADMINPASSWORD = "supersecret";
        ME_CONFIG_MONGODB_URL = "mongodb://root:supersecret@mongo:27017/";
        ME_CONFIG_BASICAUTH = "false";
        ME_CONFIG_MONGODB_ENABLE_ADMIN = "true";
      };
      dependsOn = [ "mongo" ];
      autoStart = true;
    };
  };

  # Ensure the host directory for MongoDB data exists with correct permissions
  systemd.tmpfiles.rules = [
    # Type Path Mode UID GID Age Argument
    # Create /opt/mongodb/data as directory, mode 0755, owned by root:root
    "d /opt/mongodb/data 0755 root root - -"
  ];
}
