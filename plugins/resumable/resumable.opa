package resumable

type Resumable.t = {
  (-> void) cancel,
  (-> void) upload,
  (-> void) pause,
  (-> int) getSize,
  (-> float) progress,
  (-> bool) isUploading
}

// Abstract of HTML 5 File objects.
type File.t = {
  string name,
  string `type`,
  int size
}

// Abstraction of the ResumableFile object (which is an overlay of HTML5 File objects).
type ResumableFile.t = {
  File.t file,
  string fileName,
  string uniqueIdentifier,
  int size,
  Resumable.t resumableObj,
  (bool -> float) progress,
  (-> void) abort,
  (-> void) cancel,
  (-> void) retry,
  (-> bool) isUploading,
  (-> bool) isComplete
}

// Chunk upload parameters.
type Resumable.params = {
  // The index of the chunk in the current upload. First chunk is 1 (no base-0 counting here).
  int chunkNumber,
  // The total number of chunks.
  int totalChunks,
  // The general chunk size. Using this value and resumableTotalSize you can calculate the total number of chunks.
  // Please note that the size of the data received in the HTTP might be lower than resumableChunkSize of this for the last chunk for a file.
  int chunkSize,
  int currentChunkSize,
  // The total file size.
  int totalSize,
  // A unique identifier for the file contained in the request.
  string identifier,
  // The original file name (since a bug in Firefox results in the file name not being transmitted in chunk multipart posts).
  string filename,
  // The original file type.
  string typ,
  // The file's relative path when selecting a directory (defaults to file name in all browsers except Chrome).
  string relativePath
}

type Resumable.options = {
  // Resumable options.

	// The target URL for the multipart POST request (Default: upload).
  string target,
  // Method to use when POSTing chunks to the server (multipart or octet) (Default: /)
  string method,
  // The size in bytes of each uploaded chunk of data. The last uploaded chunk will be at least
  // this size and up to two the size. (Default: 1*1024*1024)
  int chunkSize,
  // Make a GET request to the server for each chunks to see if it already exists.
  // If implemented on the server-side, this will allow for upload resumes even after
  // a browser crash or even a computer restart. (Default: true)
  bool testChunks,
  // Indicates how many files can be uploaded in a single session. Valid values are any positive integer and none for no limit. (Default: none)
  option(int) maxFiles,
  // The file types allowed to upload. An empty list allow any file type. (Default: []).
  list(string) fileType,
  // The maximum number of retries for a chunk before the upload is failed.
  // none for no limit. (Default: none)
  option(int) maxChunkRetries,
  // The number of milliseconds to wait before retrying a chunk on a non-permanent error.
  // none for immediate retry. (Default: none)
  option(int) chunkRetryInterval,
  // Override the function that generates unique identifiers for each file. (Default: none).
  option(ResumableFile.t -> string) generateUniqueIdentifier,

  // Added options.
  // Override the {query} and {preprocess} options.

  // Compute the sha of each chunk to upload, and add it to the query parameters, or form parameters, depending on the method (Default: false).
  bool withChunkSha,
  // Override the generation of identifier with random generation (Default: false).
  bool randomIdentifier

  // Unused options.

  // bool withCredentials
  // ?? fileTypeErrorCallback
  // int maxFileSize
  // ?? maxFilesErrorCallback
  // int minFileSize
  // ?? minFileSizeErrorCallback
  // ?? maxFilesErrorCallback
  // ?? headers
  // string fileParameterName
  // int simultaneousUploads
  // bool forceChunkSize
  // bool prioritizeFirstAndLastChunk
}

module Resumable {

	// The default options are based on the values assigned by resumable.js.
  Resumable.options defaults = {
  	target: "/",
  	method: "multipart",
  	chunkSize: 1*1024*1024,
  	testChunks: true,
    maxFiles: none,
    fileType: [],
  	maxChunkRetries: none,
    chunkRetryInterval: none,
    generateUniqueIdentifier: none,
    randomIdentifier: false,
    withChunkSha: false
  }

  /** Create a Resumable object. */
  function create(Resumable.options options) { %%Resumable.create%%(options) }

  /** Methods. */

  function assignDrop(Resumable.t resumable, string domid) { %%Resumable.assignDrop%%(resumable, domid) }
  function assignBrowse(Resumable.t resumable, string domid) { %%Resumable.assignBrowse%%(resumable, domid) }

  function addFile(Resumable.t resumable, ResumableFile.t file) { %%Resumable.addFile%%(resumable, file) }
  function removeFile(Resumable.t resumable, ResumableFile.t file) { %%Resumable.removeFile%%(resumable, file) }

  function progress(Resumable.t resumable) { %%Resumable.progress%%(resumable) }
  function pause(Resumable.t resumable) { %%Resumable.pause%%(resumable) }
  function cancel(Resumable.t resumable) { %%Resumable.cancel%%(resumable) }
  function upload(Resumable.t resumable) { %%Resumable.upload%%(resumable) }
  resume = upload // Resume after paused upload.

  function isUploading(Resumable.t resumable) { %%Resumable.isUploading%%(resumable) }
  function getSize(Resumable.t resumable) { %%Resumable.getSize%%(resumable) }

  /**
   * Helper function for uploading one file.
   * The uploader is configured to pick up ONE file of the specified type.
   * The callback function receives the identifier of the raw file so produced.
   *
   * @param browse the dom id of the input element.
   * @param typ accepted mimetypes.
   * @return The resumable object.
   */
  client function require(string browse, list(string) types, onsuccess) {
    options = {defaults with
      maxFiles: some(1), fileType: types,
      randomIdentifier: true, method: "octet",
      target: "/upload"
    }
    resumable = create(options)

    assignBrowse(resumable, browse)
    Bind.fileAdded(resumable, function (file) { file.resumableObj.upload() })
    Bind.fileSuccess(resumable, function (file) { onsuccess(file.uniqueIdentifier) })
    resumable
  }

  /** Resumable Files. */

  module File {

    function progress(ResumableFile.t file, bool relative) { %%Resumable.fileProgress%%(file, relative) }
    function abort(ResumableFile.t file) { %%Resumable.fileAbort%%(file) }
    function cancel(ResumableFile.t file) { %%Resumable.fileCancel%%(file) }
    function retry(ResumableFile.t file) { %%Resumable.fileRetry%%(file) }
    function isComplete(ResumableFile.t file) { %%Resumable.isFileComplete%%(file) }
    function isUploading(ResumableFile.t file) { %%Resumable.isFileUploading%%(file) }

    function preview(string canvasid, string iconid, File.t file) { %%Resumable.preview%%(canvasid, iconid, file) }
    function getPreview(string canvasid, string typ) { %%Resumable.getPreview%%(canvasid, typ) }
    function sendPreview(string canvasid, string typ, id, target) { %%Resumable.sendPreview%%(canvasid, typ, id, target) }

  } // END FILE

  /** Events. */

  module Bind {

    function fileSuccess(resumable, callback) { %%Resumable.onFileSuccess%%(resumable, callback) }
    function fileProgress(resumable, callback) { %%Resumable.onFileProgress%%(resumable, callback) }
    function fileError(resumable, callback) { %%Resumable.onFileError%%(resumable, callback) }
    function fileAdded(resumable, callback) { %%Resumable.onFileAdded%%(resumable, callback) }

    function uploadStart(resumable, callback) { %%Resumable.onUploadStart%%(resumable, callback) }
    function complete(resumable, callback) { %%Resumable.onComplete%%(resumable, callback) }
    function progress(resumable, callback) { %%Resumable.onProgress%%(resumable, callback) }
    function error(resumable, callback) { %%Resumable.onError%%(resumable, callback) }
    function pause(resumable, callback) { %%Resumable.onPause%%(resumable, callback) }
    function cancel(resumable, callback) { %%Resumable.onCancel%%(resumable, callback) }

  } // END BIND

}
