import '../core/tool.dart';
import '../services/image_generation_service.dart';

/// Tool for generating images using Stable Diffusion
class GenerateImageTool {
  static Tool create() {
    return Tool(
      name: 'generate_image',
      description: '''Generate an image using Stable Diffusion based on a text prompt.
The image will be saved to the file system storage in the generated/ folder.
Returns the file information including file_id, file_name, and relative_path.''',
      parameters: {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': 'The text description of the image to generate',
          },
          'negative_prompt': {
            'type': 'string',
            'description':
                'Things to avoid in the image (optional, defaults to "blurry, low quality, deformed")',
          },
          'steps': {
            'type': 'integer',
            'description':
                'Number of diffusion steps (optional, default: 25, range: 1-150)',
            'minimum': 1,
            'maximum': 150,
          },
          'width': {
            'type': 'integer',
            'description': 'Image width in pixels (optional, default: 1024)',
            'enum': [512, 768, 1024],
          },
          'height': {
            'type': 'integer',
            'description': 'Image height in pixels (optional, default: 1024)',
            'enum': [512, 768, 1024],
          },
        },
        'required': ['prompt'],
      },
      handler: (args) async {
        try {
          final service = ImageGenerationService.instance;

          if (!service.isConfigured) {
            return const ToolResult.failure(
              'Image generation API not configured. Please set the API URL in Settings.',
            );
          }

          final prompt = args['prompt'] as String;
          final negativePrompt = args['negative_prompt'] as String?;
          final steps = args['steps'] as int? ?? 25;
          final width = args['width'] as int? ?? 1024;
          final height = args['height'] as int? ?? 1024;

          final fileItem = await service.generateImage(
            prompt: prompt,
            negativePrompt: negativePrompt,
            steps: steps,
            width: width,
            height: height,
          );

          return ToolResult.success({
            'file_id': fileItem.id,
            'file_name': fileItem.name,
            'relative_path': fileItem.relativePath,
            'folder_path': fileItem.folderPath,
            'size': fileItem.size,
            'message': 'Image generated successfully and saved to file system',
          });
        } catch (e) {
          return ToolResult.failure('Failed to generate image: $e');
        }
      },
    );
  }
}
