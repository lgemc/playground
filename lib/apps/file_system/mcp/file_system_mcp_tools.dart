import 'package:agenix/agenix.dart';
import '../services/file_system_storage.dart';
import '../models/derivative_artifact.dart';

/// Tool to list folders in a specific path
class ListFoldersTool extends Tool {
  final FileSystemStorage _storage;

  ListFoldersTool(this._storage)
      : super(
          name: 'list_folders',
          description: 'List all folders in a specific path. Parameter: path (use "/" for root, or folder path like "documents/")',
          parameters: [
            ParameterSpecification(
              name: 'path',
              type: 'String',
              description: 'The folder path to list. Use "/" for root. Example: "documents/" or "images/"',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      String path = params['path'] as String? ?? '/';

      // Normalize path: "/" means root (empty string), otherwise ensure trailing slash
      if (path == '/') {
        path = '';
      } else if (!path.endsWith('/') && path.isNotEmpty) {
        path = '$path/';
      }

      final folders = await _storage.getFoldersInPath(path);

      final foldersInfo = folders.map((folder) => {
        'name': folder.name,
        'path': folder.path,
        'parent_path': folder.parentPath,
      }).toList();

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Found ${folders.length} folders in path: ${path.isEmpty ? "root" : path}',
        data: {'folders': foldersInfo, 'current_path': path},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to list folders: $e',
      );
    }
  }
}

/// Tool to list files in a folder
class ListFilesTool extends Tool {
  final FileSystemStorage _storage;

  ListFilesTool(this._storage)
      : super(
          name: 'list_files',
          description: 'List all files in a specific folder. Parameter: folder_path (use "" for root folder)',
          parameters: [
            ParameterSpecification(
              name: 'folder_path',
              type: 'String',
              description: 'The folder path to list files from. Use empty string "" for root folder. Example: "documents/" or "images/"',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      String folderPath = params['folder_path'] as String? ?? '';

      // Ensure trailing slash if not empty
      if (folderPath.isNotEmpty && !folderPath.endsWith('/')) {
        folderPath = '$folderPath/';
      }

      final files = await _storage.getFilesInFolder(folderPath);

      final filesInfo = files.map((file) => {
        'id': file.id,
        'name': file.name,
        'path': file.relativePath,
        'folder': file.folderPath,
        'mime_type': file.mimeType ?? 'unknown',
        'size': file.size,
        'is_favorite': file.isFavorite,
        'created_at': file.createdAt.toIso8601String(),
        'has_derivatives': false, // Will be checked separately if needed
      }).toList();

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Found ${files.length} files in folder: ${folderPath.isEmpty ? "root" : folderPath}',
        data: {'files': filesInfo, 'folder_path': folderPath},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to list files: $e',
      );
    }
  }
}

/// Tool to get file information including derivatives
class GetFileInfoTool extends Tool {
  final FileSystemStorage _storage;

  GetFileInfoTool(this._storage)
      : super(
          name: 'get_file_info',
          description: 'Get detailed information about a specific file, including whether it has derivatives. Required parameter: file_id',
          parameters: [
            ParameterSpecification(
              name: 'file_id',
              type: 'String',
              description: 'The ID of the file to get information about',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final fileId = params['file_id'] as String?;
      if (fileId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: file_id',
        );
      }

      final file = await _storage.getFileById(fileId);
      if (file == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'File not found with id: $fileId',
        );
      }

      final hasDerivatives = await _storage.hasDerivatives(fileId);
      final derivatives = hasDerivatives
          ? await _storage.getDerivatives(fileId)
          : <DerivativeArtifact>[];

      final fileInfo = {
        'id': file.id,
        'name': file.name,
        'path': file.relativePath,
        'folder': file.folderPath,
        'mime_type': file.mimeType ?? 'unknown',
        'size': file.size,
        'is_favorite': file.isFavorite,
        'created_at': file.createdAt.toIso8601String(),
        'updated_at': file.updatedAt.toIso8601String(),
        'has_derivatives': hasDerivatives,
        'derivatives_count': derivatives.length,
        'derivatives': derivatives.map((d) => {
          'id': d.id,
          'type': d.type,
          'status': d.status,
          'created_at': d.createdAt.toIso8601String(),
          'completed_at': d.completedAt?.toIso8601String(),
        }).toList(),
      };

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Retrieved file information for: ${file.name}',
        data: fileInfo,
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to get file info: $e',
      );
    }
  }
}

/// Tool to read file content (for text files only)
class ReadFileContentTool extends Tool {
  final FileSystemStorage _storage;

  ReadFileContentTool(this._storage)
      : super(
          name: 'read_file_content',
          description: 'Read the content of a text file. Only works for text-based files (txt, md, json, etc.). Required parameter: file_id',
          parameters: [
            ParameterSpecification(
              name: 'file_id',
              type: 'String',
              description: 'The ID of the file to read',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final fileId = params['file_id'] as String?;
      if (fileId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: file_id',
        );
      }

      final file = await _storage.getFileById(fileId);
      if (file == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'File not found with id: $fileId',
        );
      }

      // Check if it's a text file
      final mimeType = file.mimeType ?? '';
      final isTextFile = mimeType.startsWith('text/') ||
                        mimeType.contains('json') ||
                        mimeType.contains('xml') ||
                        mimeType.contains('markdown') ||
                        file.name.endsWith('.md') ||
                        file.name.endsWith('.txt');

      if (!isTextFile) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'File is not a text file. MIME type: $mimeType. For binary files, use derivatives instead.',
        );
      }

      final fileObject = await _storage.getFileForExport(fileId);
      final content = await fileObject.readAsString();

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Read content of file: ${file.name} (${content.length} characters)',
        data: {
          'file_id': fileId,
          'file_name': file.name,
          'content': content,
          'size': content.length,
        },
        needsFurtherReasoning: true, // User may want to do something with the content
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to read file content: $e',
      );
    }
  }
}

/// Tool to read derivative content
class ReadDerivativeContentTool extends Tool {
  final FileSystemStorage _storage;

  ReadDerivativeContentTool(this._storage)
      : super(
          name: 'read_derivative',
          description: 'Read the content of a file derivative (summary, transcript, etc.). Required parameter: derivative_id',
          parameters: [
            ParameterSpecification(
              name: 'derivative_id',
              type: 'String',
              description: 'The ID of the derivative to read',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final derivativeId = params['derivative_id'] as String?;
      if (derivativeId == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: derivative_id',
        );
      }

      final derivative = await _storage.getDerivative(derivativeId);
      if (derivative == null) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Derivative not found with id: $derivativeId',
        );
      }

      if (derivative.status != 'completed') {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Derivative is not completed yet. Status: ${derivative.status}',
        );
      }

      final content = await _storage.getDerivativeContent(derivativeId);

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Read derivative content: ${derivative.type} (${content.length} characters)',
        data: {
          'derivative_id': derivativeId,
          'file_id': derivative.fileId,
          'type': derivative.type,
          'content': content,
          'size': content.length,
        },
        needsFurtherReasoning: true, // User may want to process the derivative content
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to read derivative content: $e',
      );
    }
  }
}

/// Tool to search for files
class SearchFilesTool extends Tool {
  final FileSystemStorage _storage;

  SearchFilesTool(this._storage)
      : super(
          name: 'search_files',
          description: 'Search for files by name. Required parameter: query',
          parameters: [
            ParameterSpecification(
              name: 'query',
              type: 'String',
              description: 'The search query to find files',
              required: true,
            ),
          ],
        );

  @override
  Future<ToolResponse> run(Map<String, dynamic> params) async {
    try {
      final query = params['query'] as String?;
      if (query == null || query.isEmpty) {
        return ToolResponse(
          toolName: name,
          isRequestSuccessful: false,
          message: 'Missing required parameter: query',
        );
      }

      final files = await _storage.search(query);

      final filesInfo = files.map((file) => {
        'id': file.id,
        'name': file.name,
        'path': file.relativePath,
        'folder': file.folderPath,
        'mime_type': file.mimeType ?? 'unknown',
        'size': file.size,
        'created_at': file.createdAt.toIso8601String(),
      }).toList();

      return ToolResponse(
        toolName: name,
        isRequestSuccessful: true,
        message: 'Found ${files.length} files matching "$query"',
        data: {'files': filesInfo, 'query': query, 'count': files.length},
      );
    } catch (e) {
      return ToolResponse(
        toolName: name,
        isRequestSuccessful: false,
        message: 'Failed to search files: $e',
      );
    }
  }
}

/// Factory to create all file system tools
class FileSystemToolsFactory {
  static List<Tool> createAll(FileSystemStorage storage) {
    return [
      ListFoldersTool(storage),
      ListFilesTool(storage),
      GetFileInfoTool(storage),
      ReadFileContentTool(storage),
      ReadDerivativeContentTool(storage),
      SearchFilesTool(storage),
    ];
  }
}
