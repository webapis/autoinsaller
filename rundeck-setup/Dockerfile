# Use your desired Rundeck version as base
FROM rundeck/rundeck:4.10.0

# Switch to root to install packages
USER root

# Install Python 3 and pip
RUN apt-get update && \
    apt-get install -y python3 python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create symlink so 'python' command points to python3
RUN ln -s /usr/bin/python3 /usr/bin/python

# Install the pywinrm library (required for the PyWinRM plugin)
RUN pip3 install --no-cache-dir pywinrm

# Fix log directory permissions
RUN mkdir -p /home/rundeck/var/logs && \
    chown -R rundeck:root /home/rundeck/var/logs && \
    chmod -R 755 /home/rundeck/var/logs

# Switch back to the rundeck user
USER rundeck