# Logger

Using app bus, i want an interface that allows apps and services to log things with event type, and severity, also json metadata, those must be emitted via event bus and i want a service which stores those logs into a table in sqlite.

It must be initialized with the app name and id, and this must be added to log metadata.

Apps will use an interface that only emit events type log, and other service must wait for this logs and store them