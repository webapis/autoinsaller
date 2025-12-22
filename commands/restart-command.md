Recommended Command to Apply Changes
By running docker-compose up -d again from your C:\Users\Administrator\Documents\autoinsaller directory, Docker Compose will automatically:

Compare the running containers with your configuration files.
Detect that the semaphore service's configuration has changed.
Stop, remove, and recreate only the semaphore container with the new configuration. The db container will be left untouched.
Here is the command to run:

bash
docker-compose up -d
This ensures your changes are applied correctly and is the standard practice for managing Compose-based environments.