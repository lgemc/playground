# Queues

Based on how rabbit mq works, and app bus, create a way to move events from the bugs subscribed to specific event topics to specific queues, which can be subscribed for services. those services must read the queue, if well processed then remove the message from the queue, if not message must not be removed.

Create a service to allow:

1. Configurations of sub queues
2. Wait for messages in the bus and based on configuration write messages to those queues.

Queue configuration by now will be hardcoded, messages in each queue must survive in the database, create libraries to allow services to read messages from those queues and delete them if are well processed.

Store metrics like queue messages, subscribers, and have some subscribers ids.