# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Background jobs

Start SolidQueue workers from the project root so relative paths resolve correctly and ensure required environment variables are set:

```
OPENAI_API_KEY=your_key SERPAPI_KEY=your_key bin/jobs start
```

Use `bin/rails solid_queue:health` to display worker heartbeats and pending jobs.
