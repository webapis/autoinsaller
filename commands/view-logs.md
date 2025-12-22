# Viewing Container Logs

You can easily view the real-time logs of the `semaphore` container to monitor its activity or troubleshoot issues.

The primary command for this is `docker-compose logs`. To stream the logs live, you add the `--follow` (or `-f`) flag.

## Command to View Real-Time Logs

From your project directory (`C:\Users\Administrator\Documents\autoinsaller`), run the following command:

```bash
docker-compose logs -f semaphore
```

**What this command does:**
*   `docker-compose logs`: Fetches the logs from the services defined in your `docker-compose.yml` file.
*   `-f` or `--follow`: Instructs Docker to "follow" the log output, streaming new log entries to your terminal in real-time.
*   `semaphore`: Specifies that you only want to see the logs for the `semaphore_ui` container.

To stop watching the logs, simply press `Ctrl+C`.

## Viewing Recent Logs (Without Following)

If you don't need a real-time stream and just want to see the most recent log entries, you can use the `--tail` option. For example, to see the last 50 lines:

```bash
docker-compose logs --tail=50 semaphore
```

This is very useful for quickly checking the application's status or recent errors without being attached to a live stream.