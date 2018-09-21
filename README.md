An ECS DaemonSet to run 1 container per container instance to periodically polls the EC2 Spot Instance Termination Notices endpoint.
Once a termination notice is received, it will try to update container instance status to `DRAINING`.


Required access to container instance metadata,  please set `network mode` to `host` in task-definition.
