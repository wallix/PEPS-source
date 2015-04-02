/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */



/** Basic file module. Handles file duplication, by computing a SHA-512, and support chunked uploads. */
package com.mlstate.webmail.model

abstract type RawFile.id = DbUtils.oid

type RawFile.chunk = {
  binary sha,
  int number,
  int size
}

type Chunk.t = {
  binary sha,
  binary data
}

type RawFile.thumbnail = {
  binary sha,
  string mimetype,
  int size
}

type RawFile.content =
  { binary bytes } or                       // Clear content.
  { list({int number, string data}) chunks, // Encrypted content.
    string userPublicKey,
    string filePublicKey,
    string fileSecretKey, // Added by file token.
    string tokenNonce,    // Added by file token.
    string fileNonce }


type RawFile.t = {
  // File metadata.
  RawFile.id id,                // Unique id.
  string name,                  // File name.
  int size,                     // File size in bytes.
  string mimetype,              // File mimetype.
  // File chunks.
  list(RawFile.chunk) chunks,   // File chunks.
  int totalchunks,              // Expected number of chunks.
  // File encryption.
  option(string) password,      // File password.
  File.encryption encryption,   // File encryption (see model/file.opa).
  // File information, and versioning.
  option(RawFile.thumbnail) thumbnail,
  User.key owner,               // File owner.
  File.id file,                 // The original file.
  int version,                  // Version number.
  option(RawFile.id) previous,  // Previous version.

  Date.date created,            // Upload date.
  option(Date.date) downloaded, // Last download date.
  int count,                    // Download counter.
  bool deleted                  // File deleted.
}

// Metadata only.
type RawFile.metadata = {
  RawFile.id id,                // Unique id.
  User.key owner,               // Owner the the raw file.
  File.id file,                 // The original file.
  string name,                  // File name.
  int size,                     // File size in bytes.
  string mimetype,              // File mimetype.
  Date.date created,            // Upload date.
  option(RawFile.thumbnail) thumbnail,
  File.encryption encryption
}

// Contains the chunks.
database Chunk.t /rawdata/chunks[{sha}]
// Contains the metadata.
database RawFile.t /webmail/rawfiles[{id}]
database /webmail/rawfiles[_]/deleted = false
database /webmail/rawfiles[_]/thumbnail = none


module RawFile {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[RawFile]", msg) }
  private function debug(msg) { Log.debug("[RawFile]", msg) }

  @stringifier(RawFile.id) function sofid(RawFile.id id) { id }
  function RawFile.id idofs(string id) { id }
  RawFile.id dummy = DbUtils.OID.dummy

  /** Chunk a binary. */
  function chunk(binary, chunkSize) {
    length = Binary.length(binary)
    // Chunk the binary between the given start and its end.
    // Chunk are inserted in the database as soon as created.
    recursive function dochunk(number, start, parts) {
      if (length-start <= 2*chunkSize)
        [Chunk.make(Binary.get_binary(binary, start, length-start), number) | parts] |> List.rev
      else
        dochunk(number+1, start+chunkSize, [Chunk.make(Binary.get_binary(binary, start, chunkSize), number) | parts])
    }
    // Apply to the binary.
    dochunk(1, 0, [])
  }

  /** {1} File creation. */

  /**
   * Create a raw file.
   * The file contents is chunked to fit mongo chunk size limitations.
   */
  function RawFile.t create(User.key owner, name, mimetype, binary data, file, version, previous) {
    sha = Crypto.Hash.sha512(data)
    size = Binary.length(data)
    chunkSize = 1024 * 1024 * 1 // Same as resumable.js's default value.
    chunks = chunk(data, chunkSize)
    totalchunks = List.length(chunks)
    raw = ~{
      id: DbUtils.OID.gen(),
      name, size, mimetype,
      chunks, totalchunks,
      owner, password: none,
      file, version, previous,
      created: Date.now(),
      downloaded: none, thumbnail: none,
      count: 0, deleted: false,
      encryption: {none}
    }
    /webmail/rawfiles[id == raw.id] <- raw
    raw
  }

  /** Initiate the creation of a raw file. */
  function init(User.key owner, RawFile.id id, name, mimetype, size, totalchunks) {
    if (not(exists(id))) {
      raw = ~{
        id, name, size, mimetype,
        chunks: [], totalchunks,
        owner, password: none,
        file: File.dummy, version: 0, previous: none,
        created: Date.now(),
        downloaded: none, thumbnail: none,
        count: 0, deleted: false,
        encryption: {none}
      }

      /webmail/rawfiles[id == id] <- raw
    }
  }

  /**
   * Conclude the creation of a raw file. All extra parameters are given here.
   * Return false if the file is incomplete (missing chunks), else true (and sorts the chunks in memory).
   */
  function finish(RawFile.id id, file, version, previous) {
    raw = /webmail/rawfiles[id == id].{chunks, totalchunks}
    if (List.length(raw.chunks) < raw.totalchunks) false
    else {
      chunks = List.sort_by(_.number, raw.chunks)
      /webmail/rawfiles[id == id] <- ~{file, version, previous, chunks}
      true
    }
  }

  /** Return the URI associated with a raw file. */
  @expand function makeURI(RawFile.id id, string name) {
    id = Uri.encode_string(RawFile.sofid(id))
    name = Uri.encode_string(name)
    "/raw/{id}/{name}"
  }

  /**
   * Add a thumbnail to the specified file.
   * The thumbnail can have its own, separate mimetype, and is stored just like a chunk.
   * If the preview's size exceed mongo file limit, the preview is not uploaded.
   */
  function addThumbnail(RawFile.id id, binary data, string mimetype) {
    match (RawFile.getMetadata(id)) {
      case {some: raw}:
        sha = Crypto.Hash.sha512(data)
        size = Binary.length(data)
        if (size < 10000000) { // Size limit.
          Db.remove(@/webmail/rawfiles[id == id]/thumbnail) // PATCH for mongo error.
          // Remove previous thumbnail.
          match (raw.thumbnail) {
            case {some: thumbnail}: Chunk.remove(thumbnail.sha)
            default: void
          }
          // Add thumbnail.
          /webmail/rawfiles[id == id] <- {thumbnail: {some: ~{sha, mimetype, size}}}
          /rawdata/chunks[sha == sha] <- ~{sha, data}
          // Propagate to tokens.
          DbSet.iterator(/webmail/filetokens[active == id]/id) |>
          Iter.iter(function (id) { Db.remove(@/webmail/filetokens[id == id]/thumbnail) }, _)
          /webmail/filetokens[active == id] <- {thumbnail: {some: ~{sha, mimetype, size}}}
        }
      default: void
    }
  }

  /** {1} Chunk management. */

  module Chunk {
    /** Upload an hashed chunk. */
    exposed function upload(string sha, string data) {
      sha = Binary.of_base64(sha)
      /rawdata/chunks[sha == sha] <- ~{sha, data: Binary.of_base64(data)}
    }

    /** Create a chunk. */
    function make(binary data, int number) {
      size = Binary.length(data)
      sha = Crypto.Hash.sha512(data)
      if (not(exists(sha))) /rawdata/chunks[sha == sha] <- ~{sha, data}
      ~{size, sha, number}
    }

    function has(RawFile.id id, int number) {
      DbUtils.option(/webmail/rawfiles[id == id and chunks[_].number == number]) |> Option.is_some
    }

    /** Insert a chunk in the rawdata memory, and add it to the specified raw file. */
    function insert(RawFile.id id, int number, int size, binary data, option(binary) sha) {
      sha = sha ? Crypto.Hash.sha512(data)
      add(id, number, size, sha)
      /rawdata/chunks[sha == sha] <- ~{sha, data}
    }

    /**
     * If the chunk is already in memory (from a previous upload of the same file for example).
     * No checks performed.
     */
    function add(RawFile.id id, int number, int size, binary sha) {
      debug("Chunk.add: raw:{id} chunk:{number}")
      /webmail/rawfiles[id == id]/chunks <+ ~{number, sha, size}
    }

    /** Determine whether a chunk is being used by any file in memory. */
    function used(binary sha) {
      DbUtils.option(/webmail/rawfiles[chunks[_].sha == sha; limit 1]) |> Option.is_some
    }

    /** Same as {used}, but don't check the use of a chunk. */
    function exists(binary sha) {
      Db.exists(@/rawdata/chunks[sha == sha])
    }

    /**
     * Remove a chunk from the memory.
     * The chunk is effectively removed only when not used anymore.
     */
    function remove(binary sha) {
      if (not(used(sha)))
        Db.remove(@/rawdata/chunks[sha == sha])
    }
  } // END CHUNK

  /** {1} Getters. */

  function get(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false])
  }
  function getMetadata(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false].{id, size, mimetype, created, thumbnail, name, encryption, owner, file})
  }
  function getName(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/name)
  }
  function getOwner(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/owner)
  }
  function get_size(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/size)
  }
  function get_mimetype(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/mimetype)
  }
  function get_file(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/file)
  }
  function get_version(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/version)
  }
  function get_previous(RawFile.id id) {
    DbUtils.option(/webmail/rawfiles[id == id and deleted == false]/previous)
  }
  function is_deleted(RawFile.id id) {
    ?/webmail/rawfiles[id == id]/deleted ? true
  }

  /** Return the file's public key (or an empty string). */
  function publicKey(RawFile.id id) {
    match (?/webmail/rawfiles[id == id]/encryption) {
      case {some: ~{key ...}}: key
      default: ""
    }
  }

  /**
   * Reassemble the chunks from the memory, to form the file content.
   * If chunks are missing, it will return an empty binary instead of
   * the concatenation of the present chunks.
   *
   * Two possible results, depending on the file's encryption:
   *   - if the file is not encrypted, return a record with a single field 'bytes'
   *     containing the full binary assembled as described above.
   *   - if the file is encrypted, return a record with the encrypted chunks, and
   *     the file's encryption parameters.
   */

  function RawFile.content getContent(RawFile.t raw) {
    if (raw.deleted || List.length(raw.chunks) < raw.totalchunks)
      {bytes: Binary.create(0)}
    else
      match (raw.encryption) {
        case {none}: {bytes: getBytes(raw)}
        case ~{nonce, key}:
          chunks = getChunks(raw)
          owner = raw.owner
          // Disambiguation between user and team publicKeys is performed
          // by the function User.publicKey.
          userPublicKey = User.publicKey(owner)
           ~{ chunks, filePublicKey: key, userPublicKey, fileNonce: nonce,
              fileSecretKey: "", tokenNonce: "" }
      }
  }

  /** Return the byte content of a file (no encryption check). */
  function getBytes(RawFile.t raw) {
    bytes = Binary.create(0)
    List.iter(function (chunk) {
      match (?/rawdata/chunks[sha == chunk.sha]/data) {
        case {some: data}: Binary.add_binary(bytes, data)
        default: void
      }
    }, raw.chunks)
    bytes
  }

  /** Return the chunks forming the file, without concatenating them. */
  function getChunks(RawFile.t raw) {
    List.fold(function (chunk, chunks) {
      match (?/rawdata/chunks[sha == chunk.sha]/data) {
        case {some: data}:
          data = Binary.to_base64(data)
          [~{data, number: chunk.number}|chunks]
        default: chunks
      }
    }, raw.chunks, []) |> List.rev
  }

  /** Return the file as a resource (basic metadata with raw content). */
  function getResource(RawFile.id id) {
    match (get(id)) {
      case {some: raw}:
        if (raw.encryption == {none})
          some({
            filename: raw.name,
            resource: Resource.binary(getBytes(raw), raw.mimetype)
          })
        else none
      default: none
    }
  }

  /** Return the file as an attachment (for the API). */
  function getAttachment(RawFile.id id, bool data) {
    match (get(id)) {
      case {some: raw}:
        if (data) some({attachmentId: "{id}", size: raw.size, data: getBytes(raw)})
        else      some({attachmentId: "{id}", size: raw.size})
      default: none
    }
  }

  /** Another form of file attachments. */
  function getPayload(RawFile.id id, string partId) {
    match (get(id)) {
      case {some: raw}:
        some(~{
          partId, parts: [],
          mimeType: raw.mimetype, filename: raw.name,
          headers: [], body: {attachmentId: "{id}", size: raw.size, data: ""},
        })
      default: none
    }
  }

  /** {1} Mimetype properties. */

  function is_image(string mimetype) { String.has_prefix("image", mimetype) }

  /** {1} Querying. */

  /** test the existence of a raw file. */
  function exists(RawFile.id id) { Db.exists(@/webmail/rawfiles[id == id]) }

  /** Return the link (path) at which the file is accessible. */
  function get_raw_link(RawFile.id id) {
    match (getName(id)) {
      case {some: name}:
        sanname = Uri.encode_string(name)
        sanid = Uri.encode_string("{id}")
        {some: "/raw/{sanid}/{sanname}"}
      default: {none}
    }
  }

  /** Return the image preview, if uploaded. */
  function get_thumbnail(RawFile.id id) {
    Option.bind(get_raw_thumbnail, get(id))
  }

  /**
   * Fetch the thumbnail, if existing, of the provided raw.
   * @param raw contains at least the fiel {thumbnail} of the type {RawFile.t}
   */
  function get_raw_thumbnail(raw) {
    match (raw.thumbnail) {
      case {some: thumbnail}:
        data = ?/rawdata/chunks[sha == thumbnail.sha]/data ? Binary.create(0)
        some({size: thumbnail.size, data: data, mimetype: thumbnail.mimetype})
      default: none
    }
  }

  /**
   * Return the tokens pointing to this file, regardless of the owner.
   * Move to model/file_token.opa ?
   */
  function tokens(RawFile.id raw) {
    DbSet.iterator(/webmail/filetokens[active == raw].{id, owner})
  }

  /** {1} Modifiers. */

  /**
   * Encrypt a raw file. The content is in fact encrypted client side, this function
   * only updates the chunks and encryption of the raw file in memory.
   */
  function encrypt(RawFile.id id, chunks, encryption) {
    /webmail/rawfiles[id == id] <- ~{chunks, encryption}
  }

  /** Rename a version. */
  function rename(RawFile.id id, newname) {
    log("rename: id={id} newname={newname}")
    /webmail/rawfiles[id == id] <- {name: newname; ifexists}
  }

  /** Delete the raw file, but does not remove it from the database. */
  function delete(RawFile.id id) {
    /webmail/rawfiles[id == id]/deleted <- true
  }

  /** Remove a file and all its chunks. */
  function purge(RawFile.id id) {
    log("purge: removing raw file {id}")
    match (?/webmail/rawfiles[id == id].{chunks, thumbnail}) {
      case {some: raw}:
        List.iter(function (chunk) { Chunk.remove(chunk.sha) }, raw.chunks)
        Option.iter(function (thumb) { Chunk.remove(thumb.sha) }, raw.thumbnail)
      default: void
    }
    Db.remove(@/webmail/rawfiles[id == id])
  }
  cancel = purge

}
