# summaries

When i am navigating the file system app and find a text file, like pdf or markdown i want to be able to share it with a summary app which:

1. Can process the file type and extract the raw text (write shared libraries to do so, per now support pdf files)
2. Call our already implemented completions api (or other endpoint if required) with the raw text, with a prompt, in order to get a text summary with the main information inside the file.
3. It must then have a summary text, and a file reference, refer only the file id, not the path because path or name can change (check the file system service to know if it is possible).
4. When the file path is taped it must open the file on its folder and select it (modify the file system app if required to support it).
5. The summary must be another file in mark down, store it in the file system.
6. Handle the summary task after sharing released as a queue, and create a summarizer service which listens this queue and perform the summary.