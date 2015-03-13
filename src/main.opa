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


package com.mlstate.webmail

import stdlib.crypto

log = Log.notice("Main: ", _)
debug = Log.debug("Main: ", _)
warning = Log.warning("Main: ", _)

// Content

headers =
  Xhtml.of_string_unsafe("
<!--[if lt IE 9]>
<script src=\"/resources/js/html5shiv.min.js\"></script>
<![endif]-->") <+>
  <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"></meta>
  <meta name="viewport" content="width=device-width,initial-scale=1"></meta>
  <link rel="stylesheet" type="text/css"
        href={Utils.auto_version("/resources/css/style.css")}></link>
  <link rel="stylesheet" type="text/css"
        href={Utils.auto_version("/resources/css/icons.css")}></link> <+>
  Xhtml.of_string_unsafe("
<!--[if IE]>
<link rel=\"stylesheet\" type=\"text/css\" href=\"/resources/css/jquery-ui-bootstrap/jquery-ui-1.9.2.ie.css\"/>
<![endif]-->")

// Main

protected function build_main_page(string url) {
  state = Login.get_state()
  urn = URN.parse(url) ? URN.init
  logged = Login.is_logged(state)

  ( if (logged
      )
      TopbarView.build(state, urn.mode) else <></> ) <+>
  ( if ((logged && not(User.key_exists(state.key))) || (url == "/register"))
      WB.Layout.fixed(AdminView.register(state, none))
    else {
      // URN.set(urn): To be done after construction of the page.
      sidebar = SidebarView.build(state, urn.mode)
      content = Content.build(state, urn)
      sidebar <+> content
    } ) <+>
  Footer.build(state)
}

protected function main(string s) {
  Resource.full_page_with_doctype(
    AppText.app_title(), {html5},
    build_main_page(s),
    headers, {success}, []
  )
}

/** Address autocompletion. */
function addresses() {
  state = Login.get_state()
  if (Login.is_logged(state))
    match (HttpRequest.get_url()) {
      case {some: url}:
        term = List.assoc("q", url.query) ? ""
        Resource.raw_text(AutoComplete.addresses(state, term))
      default: Resource.raw_response("\{\"items\": []\}", "application/json", {success})
    }
  else Resource.raw_response("\{\"items\": []\}", "application/json", {success})
}

/** {1} Chunked file upload. */

module Chunk {

  /** Return true iff the chunk is missing. */
  function test() {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Resource.raw_text(AppText.login_please())
    else {
      url = HttpRequest.get_url()
      chunkNumber = Http.Query.int("resumableChunkNumber", url)
      totalChunks = Http.Query.int("resumableTotalChunks", url)
      chunkSize = Http.Query.int("resumableChunkSize", url)
      totalSize = Http.Query.int("resumableTotalSize", url)
      typ = Http.Query.string("resumableType", url)
      identifier = Http.Query.string("resumableIdentifier", url)
      filename = Http.Query.string("resumableFilename", url)
      // relativePath = Http.Query.string("resumableRelativePath", url)

      match ((chunkNumber, totalChunks, chunkSize, totalSize, typ, identifier, filename)) {
        case ({some: chunkNumber}, {some: totalChunks},
              {some: chunkSize}, {some: totalSize},
              {some: typ}, {some: identifier},
              {some: filename}):
          identifier = RawFile.idofs(identifier)
          sha = Http.Query.binary("resumableChunkSha", url)
          // Create the raw file, if not already open.
          RawFile.init(state.key, identifier, filename, typ, totalSize, totalChunks)
          // Check for need to upload chunk.
          if (RawFile.Chunk.has(identifier, chunkNumber)) {
            debug("Chunk.test: {identifier} {chunkNumber} ~> chunk present")
            Http.Json.success({})
          }else if (Option.map(RawFile.Chunk.exists, sha) ? false) {
            debug("Chunk.test: {identifier} {chunkNumber} ~> chunk exists")
            RawFile.Chunk.add(identifier, chunkNumber, chunkSize, sha ? Binary.create(0))
            Http.Json.success({})
          }else {
            debug("Chunk.test: {identifier} {chunkNumber} ~> chunk missing")
            Http.Json.no_content("Chunk not found")
          }
        default:
          warning("Chunk.test: missing parameters")
          Http.Json.bad_request("Missing parameters")
      }
    }
  }

  /** Upload a chunk. */
  function upload() {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Resource.raw_text(AppText.login_please())
    else {
      headers = HttpRequest.get_headers()
      format = Option.bind(_.header_get("content-type"), headers) ? ""
      multipart = String.has_prefix("multipart/form-data", String.lowercase(format))
      octet = String.has_prefix("application/octet-stream", String.lowercase(format))
      if (multipart) {
        warning("Chunk.upload: multipart: non supported")
        Http.Json.bad_request("Unsupported format")
      }else if (octet || format == "") {
        url = HttpRequest.get_url()
        data = HttpRequest.get_bin_body()

        chunkNumber = Http.Query.int("resumableChunkNumber", url)
        totalChunks = Http.Query.int("resumableTotalChunks", url)
        chunkSize = Http.Query.int("resumableChunkSize", url)
        totalSize = Http.Query.int("resumableTotalSize", url)
        typ = Http.Query.string("resumableType", url)
        identifier = Http.Query.string("resumableIdentifier", url)
        filename = Http.Query.string("resumableFilename", url)

        match ((chunkNumber, totalChunks, chunkSize, totalSize, typ, identifier, filename, data)) {
          case ({some: chunkNumber}, {some: totalChunks},
                {some: chunkSize}, {some: totalSize},
                {some: typ}, {some: identifier},
                {some: filename}, {some: data}):
            debug("Chunk.upload: octet: {chunkNumber}/{totalChunks}")
            identifier = RawFile.idofs(identifier)
            // Create the raw file, if not already open.
            RawFile.init(state.key, identifier, filename, typ, totalSize, totalChunks)
            // Upload chunk.
            RawFile.Chunk.insert(identifier, chunkNumber, chunkSize, data, none)
            Http.Json.success({})
          default:
            warning("Chunk.upload: missing parameters")
            Http.Json.bad_request("Missing parameters")
        }
      }else {
        warning("Chunk.upload: unrecognized format: '{format}'")
        Http.Json.bad_request("Unrecognized format")
      }
    }
  }
} // END CHUNK

/** Parse data urls. */
dataUrl = parser {
  "data:image/" typ=("png"|"jpeg") ";base64," data=(.*): (typ, Text.to_string(data))
}

/** Receive image previews, and push them to the database. */
function thumbnail() {
  state = Login.get_state();
  if (not(Login.is_logged(state)))
    Resource.raw_text(AppText.login_please())
  else {
    url = HttpRequest.get_url()
    typ = Http.Query.string("resumableType", url)
    identifier = Http.Query.string("resumableIdentifier", url)

    match ((identifier, typ)) {
      case ({some: identifier}, {some: typ}):
        match (Option.bind(Parser.try_parse(dataUrl, _), HttpRequest.get_body())) {
          case {some: (_typ, data)}:
            data = Binary.of_base64(data)
            RawFile.add_thumbnail(RawFile.idofs(identifier), data, typ)
            Http.Json.success({})
          default:
            warning("thumbnail: corrupt body")
            Http.Json.bad_request("Corrupt body")
        }
      default:
        warning("thumbnail: missing parameters")
        Http.Json.bad_request("Missing parameters")
    }
  }
}

/** App Server. */

resources = @static_resource_directory("resources")
favicon = @static_resource("resources/img/favicon.ico")

dispatcher = parser {
  // Api.
  case resource=RestApi.dispatcher: resource

  case "/null": Resource.raw_status({success})

  // Resources
  case "/favicon" .* : favicon
  case r={Server.resource_map(resources)} .* : r

  // Shared resources urls
  case t=(.*):
    GET = Http.Method.get()
    POST = Http.Method.post()

    parser {
      // Special URLs
      case       "/search/addresses" .*: addresses()
      case       "/raw" s=(.*) : FileView.download(Text.to_string(s), Notifications.build)
      case GET   "/upload" ("?" .*)?: Chunk.test()
      case POST  "/upload" ("?" .*)?: Chunk.upload()
      case POST  "/thumbnail" ("?" .*)? : thumbnail()
      case GET   "/thumbnail/" raw=(.*): FileController.download_thumbnail(Text.to_string(raw))
      case GET   "/avatar/" user=(.*): UserController.downloadAvatar(Text.to_string(user))
      // Main
      case s=(.*) : main(Text.to_string(s))
    } |> Parser.Text.parse(_, t)
}

Resource.register_external_js("/resources/js/jquery-ui-1.9.2.custom.min.js")
Resource.register_external_js("/resources/js/jquery.tokeninput.js")
Resource.register_external_js("/resources/js/select2.full.js")
Resource.register_external_js(Utils.auto_version("/resources/js/mail.js"))
Resource.register_external_css("/resources/css/tablesorter.css")
Resource.register_external_css("/resources/css/select2.min.css")

private server encryption =
  if (AppParameters.parameters.no_ssl) {no_encryption: void}
  else {
    certificate : "{AppConfig.peps_dir}/server.crt",
    private_key : "{AppConfig.peps_dir}/server.key",
    password : ""
  }

/** Start peps server. */
Server.start(
  { port: AppParameters.parameters.http_server_port ? AppConfig.http_server_port,
    netmask: 0.0.0.0, name: "peps", ~encryption },
  [ {register: [{doctype:{html5}}]},
    {custom : dispatcher} ]
)

/** Start stmp in. */
Server.start(
  { port: AppParameters.parameters.smtp_in_port, netmask: 0.0.0.0, encryption: {no_encryption}, name: "smtp-in" },
  [ {custom: parser {
    case "/domain":
      domain = Admin.get_domain()
      Log.notice("[SMTPin]", "domain: {domain}")
      Resource.raw_response("{domain}", "text/simple", {success})
    case url=(.*):
      Log.notice("[SMTPin]", "default: {Text.to_string(url)}")
      SmtpController.receive()
  }} ]
)
