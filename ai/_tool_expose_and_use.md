# Tool use

I want to expose tool usage to the main chat from the other apps.

Lets design the required changes/improvements to allow this (use mcp maybe, or general tool use, you decide) and add support for the chat to use them, let start with something simple: vocabulary creation

In the chat when is written: add nuances to vocabulary, the chat must internally call the already existing functionality to 
create this inside vocabulary app.

Check that vllm and chatgpt libraries and apis already has tool calling support. add this tool calling to the core and add a service to use it, per now use it inside the chat. 