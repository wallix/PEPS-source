
/** @externType Resumable.t */
/** @externType Resumable.options */
/** @externType ResumableFile.t */
/** @externType File.t */
/** @externType dom_element */

/** @register {Resumable.options -> Resumable.t} */
function create(options) {
	var init = {
		target: options.target,
		method: options.method,
		chunkSize: options.chunkSize,
		testChunks: options.testChunks,
		fileType: []
	};
	if (options.maxChunkRetries.some) init.maxChunkRetries = options.maxChunkRetries.some;
	if (options.maxFiles.some) init.maxFiles = options.maxFiles.some;
	if (options.chunkRetryInterval.some) init.chunkRetryInterval = options.chunkRetryInterval.some;
	if (options.generateUniqueIdentifier.some) init.generateUniqueIdentifier = options.generateUniqueIdentifier.some;

  var types = options.fileType, typ = types.hd;
  while(typ){
    init.fileType.push(typ);
		types = types.tl;
    typ = types.hd;
  }

	if (options.randomIdentifier) init.generateUniqueIdentifier = function (file) {
		if (window.crypto && window.crypto.getRandomValues) {
			var hexChars = '0123456789abcdef'.split(''), keySize = 32;
			var bytes = window.crypto.getRandomValues(new Uint32Array(keySize));
	    var result = '';
	    for (var i = 0; i < keySize; i++) { result += hexChars[bytes[i] % 16]; }
      return result;
    } else
      return BslNumber.Random.string(32); // OPA random generator.
  };
	if (options.withChunkSha) {
		// Add chunk preprocessing, which computes the sha-512 digest of the chunk.
		init.preprocess = function (chunk) {
			var $ = chunk;
			cryptosubtle = window.crypto.subtle ? window.crypto.subtle : window.crypto.webkitSubtle;
			if (false) { // if (cryptosubtle) {
				var func   = ($.fileObj.file.slice ? 'slice' : ($.fileObj.file.mozSlice ? 'mozSlice' : ($.fileObj.file.webkitSlice ? 'webkitSlice' : 'slice'))),
						bytes  = $.fileObj.file[func]($.startByte,$.endByte),
						data   = new Uint8Array(bytes);
				cryptosubtle.digest({name: 'SHA-512'}, data).then(
					function (digest) {
						$.sha = digest;
						console.log("digest[sha-512]= " + digest);
						$.preprocessFinished();
					},
					function (error) { $.preprocessFinished(); }
				);
			} else $.preprocessFinished();
		}
		// Add chunk sha to query parameters.
		init.query = function (file, chunk) {
			var q = {};
			if (chunk.sha) q.resumableChunkSha = chunk.sha;
			return q;
		};
	}
	return new Resumable(init);
}

/** @register {string, string, File.t -> void} */
function preview(canvasid, iconid, file) {
  var canvas = document.getElementById(canvasid),
  		icon = document.getElementById(iconid);
  if (canvas && icon) {
    var context = canvas.getContext('2d'),
        img = new Image(),
        reader = new FileReader();
    img.onload = function(){
      var w = img.width, h = img.height,
	        cw = canvas.width, ch = canvas.height;

	    // If canvas is too large, resize while keeping proportions.
      if (w < cw || h < ch) {
      	if (h*cw > w*ch) { ch = w*ch/cw; cw = w; }
      	else { cw = h*cw/ch; ch = h; }
      	canvas.width = cw;
      	canvas.height = ch;
      }

      // Resize.
    	var sw = w, sh = h, dw = 0, dh = 0;
    	if (cw*h < ch*w) { sw = cw*h/ch; dw = (w-sw)*0.5; }
    	else { sh = ch*w/cw; dh = (h-sh)*0.5; }
    	// console.log('Resizing ['+dw+','+dh+','+sw+','+sh+'] into ['+cw+','+ch+']');

    	// For good antialiasing, follow the steps: http://stackoverflow.com/questions/17861447/html5-canvas-drawimage-how-to-apply-antialiasing.
    	// Step 1: first reduction.
    	var c = document.createElement('canvas'),
    			ctx = c.getContext('2d');
    	c.width = (sw+cw)*0.5;
      c.height = (sh+ch)*0.5;
      // console.log('Step1 ['+dw+','+dh+','+sw+','+sh+'] into ['+c.width+','+c.height+']');
      ctx.drawImage(img, dw, dh, sw, sh, 0, 0, c.width, c.height);
      // Step 2: second reduction.
      // console.log('Step2 ['+c.width+','+c.height+'] into ['+cw+','+ch+']');
      ctx.drawImage(c, 0, 0, cw, ch);
      // Step 3: redraw to canvas.
      context.drawImage(c, 0, 0, cw, ch, 0, 0, cw, ch);
      // Report preview to icon.
      icon.src = canvas.toDataURL('image/png');
    };
    reader.onloadend = function (e) {
      img.src = e.target.result;
    }
    reader.readAsDataURL(file);
  }
}

/** @register {string, string -> string} */
function getPreview(canvasid, type) {
	var canvas = document.getElementById(canvasid);
	return (canvas ? canvas.toDataURL(type) : '');
}

/** @register {string, string, string, string -> void} */
function sendPreview(canvasid, type, id, target) {
	var canvas = document.getElementById(canvasid);
	if (canvas) {
		var xhr = new XMLHttpRequest();
		var resumableIdentifier = 'resumableIdentifier='+encodeURIComponent(id),
				resumableType = 'resumableType='+encodeURIComponent(type),
				url = target+'?'+resumableIdentifier+'&'+resumableType;
		xhr.open("POST", url);
		xhr.send(canvas.toDataURL(type));
	}
}


// Methods.

/** @register {Resumable.t, string -> void} */
function assignDrop(resumable, domid) { resumable.assignDrop(document.getElementById(domid)); }

/** @register {Resumable.t, string -> void} */
function assignBrowse(resumable, domid) { resumable.assignBrowse(document.getElementById(domid)); }

/** @register {Resumable.t, ResumableFile.t -> void} */
function addFile(resumable, file) { resumable.addFile(file); }

/** @register {Resumable.t, ResumableFile.t -> void} */
function removeFile(resumable, file) { resumable.removeFile(file); }

/** @register {Resumable.t -> float} */
function progress(resumable) { return resumable.progress(); }

/** @register {Resumable.t -> void} */
function pause(resumable) { resumable.pause(); }

/** @register {Resumable.t -> void} */
function cancel(resumable) { resumable.cancel(); }

/** @register {Resumable.t -> void} */
function upload(resumable) { resumable.upload(); }

/** @register {Resumable.t -> bool} */
function isUploading(resumable) { return resumable.isUploading(); }

/** @register {Resumable.t -> int} */
function getSize(resumable) { return resumable.getSize(); }

// Files.

/** @register {ResumableFile.t, bool -> float} */
function fileProgress(file, relative) { return file.progress(relative); }

/** @register {ResumableFile.t -> void} */
function fileAbort(file) { file.abort() }

/** @register {ResumableFile.t -> void} */
function fileCancel(file) { file.cancel() }

/** @register {ResumableFile.t -> void} */
function fileRetry(file) { file.retry() }

/** @register {ResumableFile.t -> bool} */
function isFileUploading(file) { return file.isUploading() }

/** @register {ResumableFile.t -> bool} */
function isFileComplete(file) { return file.isComplete() }

// Events.

/** @register {Resumable.t, (ResumableFile.t -> void) -> void} */
function onFileSuccess(resumable, callback) { resumable.on('fileSuccess', callback); }

/** @register {Resumable.t, (ResumableFile.t -> void) -> void} */
function onFileProgress(resumable, callback) { resumable.on('fileProgress', callback); }

/** @register {Resumable.t, (ResumableFile.t -> void) -> void} */
function onFileAdded(resumable, callback) { resumable.on('fileAdded', function (file, evt) { callback(file) }); }

/** @register {Resumable.t, (ResumableFile.t, string -> void) -> void} */
function onFileError(resumable, callback) { resumable.on('fileError', callback); }

/** @register {Resumable.t, (-> void) -> void} */
function onUploadStart(resumable, callback) { resumable.on('uploadStart', callback); }

/** @register {Resumable.t, (-> void) -> void} */
function onComplete(resumable, callback) { resumable.on('complete', callback); }

/** @register {Resumable.t, (-> void) -> void} */
function onProgress(resumable, callback) { resumable.on('progress', callback); }

/** @register {Resumable.t, (string, ResumableFile.t -> void) -> void} */
function onError(resumable, callback) { resumable.on('error', callback); }

/** @register {Resumable.t, (-> void) -> void} */
function onPause(resumable, callback) { resumable.on('pause', callback); }

/** @register {Resumable.t, (-> void) -> void} */
function onCancel(resumable, callback) { resumable.on('cancel', callback); }

