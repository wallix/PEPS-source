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

module RestApi {

  /** {1} Utils. */

  private function log(msg) { Log.notice("RestApi: ", msg) }
  private function debug(msg) { Log.debug("RestApi: ", msg) }
  private function warning(msg) { Log.warning("RestApi: ", msg) }

  /** {1} Dispatcher */

  user_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) |> User.idofs }
  team_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) |> Team.idofs }
  message_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) |> Message.midofs }
  folder_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) |> Folder.idofs }
  file_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) |> File.idofs }
  string_id = parser { case s=((!"/" !"?" .)*): Text.to_string(s) }

  dispatcher = parser {

    // Upload API.
    case "/upload/api/v" api_version=Rule.integer t=(.*):
      // Rules for http methods.
      POST = Http.Method.post()
      PUT = Http.Method.put()
      GET = Http.Method.get()

      debug("Upload API URL: {Text.to_string(t)}")

      parser {

        /** Messages. */

        case POST   "/users/" uid=user_id "/messages" ("?" .*)?: Messages.insert(api_version, false)                            // Insert.
        case POST   "/users/" uid=user_id "/messages/import" ("?" .*)? : Http.Json.not_found({error: AppText.Not_found()})           // Import.
        case POST   "/users/" uid=user_id "/messages/send" ("?" .*)?: Messages.insert(api_version, true)                        // Send.

        /** Files. */

        case GET          "/files/" path=((!"?" .)*) ("?" .*)?: FS.get(api_version, Text.to_string(path))                       // Get.
        case (POST|PUT)   "/files_put/" path=((!"?" .)*) ("?" .*)?: FS.upload(api_version, Text.to_string(path))                // Upload.

      } |> Parser.Text.parse(_, t)

    // Regular API.
    case "/api/v" api_version=Rule.integer t=(.*):
      // Rules for http methods.
      GET = Http.Method.get()
      POST = Http.Method.post()
      PATCH = Http.Method.patch()
      PUT = Http.Method.put()
      DELETE = Http.Method.delete()
      OPTIONS = Http.Method.options()

      debug("API URL: {Text.to_string(t)}")

      parser {

        /** OAuth protocol. */

        case GET    "/oauth/request_token" .*:        OAuth.request_token(api_version)
        case GET    "/oauth/authorize" .*:            OAuth.authorize(api_version)
        case POST   "/oauth/access_token" .*:         OAuth.access_token(api_version)
        case GET    "/oauth/gnameadmin" .*:           OAuth.gnameadmin(api_version)
        case GET    "/oauth/logout" .*:               OAuth.logout(api_version)

        /** Direct login. */

        case POST   "/login" .*:                      login(api_version)

        /** Drafts. Function implementations in sub-module 'Drafts'. */

        case POST   "/users/" uid=user_id "/drafts": Http.Json.not_found({error: AppText.Not_found()})                          // Create.
        case DELETE "/users/" uid=user_id "/drafts/" mid=message_id: Drafts.delete(api_version, mid)                            // Delete.
        case GET    "/users/" uid=user_id "/drafts/" mid=message_id: Drafts.get(api_version, mid)                               // Get.
        case GET    "/users/" uid=user_id "/drafts": Http.Json.not_found({error: AppText.Not_found()})                          // List.
        case PUT    "/users/" uid=user_id "/drafts/" mid=message_id: Http.Json.not_found({error: AppText.Not_found()})          // Update.
        case POST   "/users/" uid=user_id "/drafts/send": Drafts.send(api_version)                                              // Send.
        case GET    "/users/" uid=user_id "/history" ("?" .*)?: Messages.History.list(api_version)                              // List.

        /** Folders. Function implementations in sub-module 'Folders'. */

        case POST   "/users/" uid=user_id "/folders" ("?" .*)?: Folders.save(api_version, none)                                 // Create.
        case DELETE "/users/" uid=user_id "/folders/" fid=folder_id ("?" .*)?: Folders.delete(api_version, fid)                 // Delete.
        case GET    "/users/" uid=user_id "/folders" ("?" .*)?: Folders.list(api_version)                                       // List.
        case PUT    "/users/" uid=user_id "/folders/" fid=folder_id ("?" .*)?: Folders.save(api_version, {some: fid})           // Update.
        case GET    "/users/" uid=user_id "/folders/" fid=folder_id ("?" .*)?: Folders.get(api_version, fid)                    // Get.
        case PATCH  "/users/" uid=user_id "/folders/" fid=folder_id ("?" .*)?: Folders.patch(api_version, fid)                  // Patch.

        /** Tags: a mix of folder and label operations. */

        case GET    "/users/" uid=user_id "/tags/" id=string_id ("?" .*)?: Tags.get(api_version, id)                            // Get.
        case GET    "/users/" uid=user_id "/tags" ("?" .*)?: Tags.list(api_version)                                             // List.
        case DELETE "/users/" uid=user_id "/tags/" id=string_id ("?" .*)?: Tags.delete(api_version, id)                         // Delete.
        case POST   "/users/" uid=user_id "/tags" ("?" .*)?: Tags.save(api_version, none)                                       // Create.
        case PUT    "/users/" uid=user_id "/tags/" id=string_id ("?" .*)?: Tags.save(api_version, some(id))                     // Update.

        /** Messages. Function implementations in sub-module 'Messages'. */

        case DELETE "/users/" uid=user_id "/messages/" mid=message_id ("?" .*)?: Messages.delete(api_version, mid)              // Delete.
        case GET    "/users/" uid=user_id "/messages/" mid=message_id ("?" .*)?: Messages.get(api_version, mid)                 // Get.
        case GET    "/users/" uid=user_id "/messages" ("?" .*)?: Messages.list(api_version)                                     // List.
        case POST   "/users/" uid=user_id "/messages/" mid=message_id "/modify" ("?" .*)?: Messages.modify(api_version, mid)    // Modify.
        case POST   "/users/" uid=user_id "/messages/send" ("?" .*)?: Messages.insert(api_version, true)                        // Send.
        case POST   "/users/" uid=user_id "/messages/" mid=message_id "/trash" ("?" .*)?: Messages.trash(api_version, mid)      // Trash
        case POST   "/users/" uid=user_id "/messages/" mid=message_id "/untrash" ("?" .*)?: Messages.untrash(api_version, mid)  // Untrash.
        // case POST   "/users/" uid=user_id "/messages/import" ("?" .*)?: Http.Json.not_found({error: AppText.Not_found()})
        // case POST   "/users/" uid=user_id "/messages" ("?" .*)?: Messages.insert(api_version)

        /** Attachments. */

        case GET    "/users/" uid=user_id "/messages/" mid=message_id "/attachments/" fid=file_id ("?" .*)?: Attachments.get(api_version, mid, fid)

        /** Threads. */

        // TODO: implement.

        /** Users. */

        case GET    "/users/history" ("?" .*)?: Users.history(api_version)                                                      // History.
        case GET    "/users/" uid=user_id ("?" .*)?: Users.get(api_version, uid)                                                // Get.
        case POST   "/users" ("?" .*)?: Users.insert(api_version)                                                               // Create new users.
        case PUT    "/users/" uid=user_id ("?" .*)?: Users.update(api_version, uid)                                             // Update existing users (except for teams).
        case GET    "/users" ("?" .*)?: Users.list(api_version)                                                                 // List.
        case DELETE "/users/" uid=user_id ("?" .*)?: Users.delete(api_version, uid)                                             // Delete.
        case PUT    "/users/" uid=user_id "/move" ("?" .*)?: Users.move(api_version, uid)                                       // Update user teams.

        /** Teams. */

        case GET    "/teams/history" ("?" .*)?: Teams.history(api_version)                                                      // History.
        case GET    "/teams/" tid=team_id ("?" .*)?: Teams.get(api_version, tid)                                                // Get.
        case POST   "/teams" ("?" .*)?: Teams.insert(api_version)                                                               // Create.
        case PUT    "/teams/" tid=team_id  ("?" .*)?: Teams.update(api_version, tid)                                            // Update.
        case DELETE "/teams/" tid=team_id ("?" .*)?: Teams.delete(api_version, tid)                                             // Delete.
        case GET    "/teams" ("?" .*)?: Teams.list(api_version)                                                                 // List.

        /** Files. */

        case GET    "/files/metadata/" path=((!"?" .)*) ("?" .*)?: FS.metadata(api_version, Text.to_string(path))               // Metadata.
        case POST   "/fileops/create_folder" ("?" .*)?: FS.create(api_version)                                                  // Folder creation.
        case POST   "/fileops/copy" ("?" .*)?: FS.move(api_version, true)                                                       // File and directory copy.
        case POST   "/fileops/delete" ("?" .*)?: FS.delete(api_version)                                                         // Deletion.
        case POST   "/fileops/move" ("?" .*)?: FS.move(api_version, false)                                                      // Move.

        // More to come ...

      } |> Parser.Text.parse(_, t)
  }

  /**
   * {1} Parsing.
   *
   * Contains parsers for query parameters such as formats, types
   * and so on.
   */

  private module Parse {

    function Message.format format(string format) {
      match (String.lowercase(format)) {
        case "minimal": {minimal}
        case "raw": {raw}
        // Default case is full.
        default: {full}
      }
    }

    function Message.upload_type upload_type(string uptype) {
      match (String.lowercase(uptype)) {
        case "multipart": {multipart}
        case "resumable": {resumable}
        // Default case is media.
        default: {media}
      }
    }

    function User.status status(string status) {
      match (String.lowercase(status)) {
        case "admin": {admin}
        case "super_admin": {super_admin}
        default: {lambda}
      }
    }

  } // END PARSE

  /** {1} Method implementations. */

  /** Version check. */
  private @expand function check_api_version(int version, int min, int max, ifok) {
    if (version >= min && version <= max) ifok()
    else Http.Json.not_supported(version)
  }

  /** Regular connection. */

  /**
   * Check the provided credentials, and generate an access token if they pass
   * the validation. The access token can then be used to sign requests made to the API,
   * in the same one would sign requests under the OAuth protocol.
   * The following parameters, with the given values, must be included in order to compute the signature:
   *
   *  consumer_key = ""
   *  consumer_secret = ""
   *  oauth_token_secret = ""
   *  oauth_verifier = ""
   *
   * along with the standard:
   *
   *  oauth_signature_method
   *  oauth_signature
   *  oauth_token
   */
  protected function login(_version) {
    // Extract user credentials from the request body.
    creds =
      HttpRequest.get_json_body() |>
      Option.bind(OpaSerialize.Json.unserialize_unsorted, _)
    match (creds) {
      case {some: ~{username, password}}:
        match (User.identify(username)) {
          case {some: key}:
            if (User.is_blocked(key)) {
              warning("login: Invalid login or password")
              Http.Json.bad_request("Invalid login or password")
            } else if (User.Password.verify(key, password)) {
              status = User.get_status(key)
              // Find a valid session token, or create
              // a new one associated with the given credentials.
              match (Sessions.find(key, status, false)) {
                case {some: token}: Http.Json.success(~{token})
                default:
                  user = ~{key: key, status, username}
                  token = Oauth.make_verified_token()
                  Sessions.create(user, some(token), false) |> ignore
                  Http.Json.success(~{token})
              }
            }else {
              warning("login: Invalid login or password")
              Http.Json.bad_request("Invalid login or password")
            }
          default:
            warning("login: Invalid login or password")
            Http.Json.bad_request("Invalid login or password")
        }
      default:
        warning("login: Missing login or password")
        Http.Json.bad_request("Missing login or password")
    }
  }

  /** OAuth connection. */
  module OAuth {

    /**
     * Extract the query parameters, check the OAuth provided version, then send
     * the parameters to the callback.
     */
    private @expand function check_oauth_version(expected, (list((string, string)) -> resource) ifok) {
      params = OauthController.parameters()
      provided = List.assoc("oauth_version", params)
      if (provided == none) // Assume OAuth version is 1.0
        ifok(params)
      else if (provided != {some: expected})
        error_page(0, @i18n("OAuth version {provided ? "_"} not supported"))
      else
        ifok(params)
    }

    /** Check both versions. */
    private @expand function check_versions(version, api, oaut, ifok) {
      check_api_version(version, api, api, function () {
        @catch(function(exn) { error_page(version, "{exn}") },
          check_oauth_version("1.0", ifok)
        )
      })
    }

    function html_or_json(html_fun, json_fun) {
      match (HttpRequest.get_headers()) {
        case {some:h}:
          match (h.header_get("Accept")) {
            case {some:accept}:
              if (String.contains(accept, "application/json")) json_fun()
              else html_fun()
            case {none}: html_fun()
          }
        case {none}: html_fun()
      }
    }

    function error_page(_version, reason) {
      function html() { Http.Html.error(reason) }
      function json() { Http.Json.success({error:reason}) }
      html_or_json(html, json)
    }

    function unauthorized_page(_version) {
      function html() { Http.Html.unauthorized() }
      function json() { Http.Json.success({error: AppText.Login_please()}) }
      html_or_json(html, json)
    }

    /** Request token endpoint. */
    function request_token(_version) {
      check_oauth_version("1.0", function (params) {
        match (OauthController.request_token(params)) {
          case {failure: reason}:
            warning("OAuth.request_token: failed with {reason}")
            Http.Form.error([("error",reason)])
          case {success: data}: Http.Form.success(data)
        }
      })
    }

    private function mini_styled_page(title, content) {
      xhtml =
        <div style="height:300px" class="login-window">
          <div class="topbar">
            <div class="fill">
              <div class="container">
                 <a class="brand" href="{Oauth.make_oauth_url("")}">{title}</a>
              </div>
            </div>
          </div>
          <div class="container content">
            {content}
          </div>
        </div>
      Resource.styled_page(title, ["/resources/css/style.css"/*, Page.bootstrap_url ??? */], xhtml)
    }

    function login(version, oauth_token, oauth_callback, uri) {
      state = Login.get_state()
      // Pre-existing connection, and user is logged in.
      if (Login.is_logged(state))
        match (OauthController.authorize(oauth_token, oauth_callback)) {
          case {failure: reason}:
            warning("Oauth.login: failed to authorize the request token {oauth_token}: {reason}")
            error_page(version, reason)
          case {success: ~{oauth_token: verified_oauth_token, oauth_callback, oauth_verifier}}:
            if (oauth_token != verified_oauth_token)
              error_page(version, "Authentication failure")
            else {
              // Create a session mapping the request token to the authenticated user.
              (username, status) =
                match (User.get(state.key)) {
                  case {some: user}: (user.username, user.status)
                  default: (state.key, {lambda})
                }
              Session.user user = ~{key:state.key, status, username}
              Sessions.create(user, some(oauth_token), false) |> ignore
              // No callback specified: display the verifier.
              if (oauth_callback == "oob")
                Resource.page("",
                  <div>
                    <h3>You are successfully logged into {Admin.get_settings().logo}</h3>
                    <p>Your token verifier is {oauth_verifier}</p>
                  </div>
                )
              // Redirect to callback.
              else
                Resource.redirection_page(
                  "Page redirection",
                  <div>If you are not redirected automatically, follow the <a href="{uri}">link to page</a></div>,
                  {success}, 0, "{oauth_callback}?oauth_verifier={oauth_verifier}&oauth_token={oauth_token}"
                )
            }
        }
      // Display login window.
      else {
        title =
          match (Oauth.get_consumer_name(oauth_token)) {
            case {some:name}: @i18n("Sign in to {name} using {Admin.get_settings().logo}")
            case {none}: @i18n("Sign in to {Admin.get_settings().logo}")
          }
        xhtml =
          <div class="home-card">
            <div class="well">
              <div class="app-icon"></div>
              <h1>{Admin.get_settings().logo}</h1>
              <h3>{AppText.sign_in_to_mailbox()}</h3>
                <div id="login">{
                  Login.build(state)
                }</div>
              {AdminView.register(state,{none})}
            </div>
          </div>
        mini_styled_page(title, xhtml)
      }
    }

    function authorize(int version) {
      log("OAuth.authorize")
      match (HttpRequest.get_url()) {
        case {none}: error_page(version, @i18n("No URL defined"))
        case {some:uri}:
          match (List.assoc("oauth_token", uri.query)) {
            case {some:oauth_token}:
              oauth_callback = List.assoc("oauth_callback", uri.query) ? "oob"
              login(version, oauth_token, oauth_callback, uri)
            default: error_page(version, @i18n("No authorization data provided"))
          }
      }
    }

    /** Access token endpoint. */
    function access_token(int version) {
      check_oauth_version("1.0", function (params) {
        log("OAuth.access_token")
        match (OauthController.access_token(params)) {
          case {failure: reason}: Http.Form.success([("error", reason)])
          case {success: data}:
            request_token = List.assoc("oauth_token", params)
            access_token = List.assoc("oauth_token", data)
            match ((request_token, access_token)) {
              case ({some: request_token}, {some: access_token}):
                Sessions.swap(request_token, access_token)
                Http.Form.success(data)
              default:
                Http.Form.success([("error", "No OAuth token")])
            }
        }
      })
    }

    function gnameadmin(int version) {
      check_versions(version, 0, "1.0", function (params) {
        debug("oauth gnameadmin")
        match (List.assoc("oauth_token", params)) {
          case {some:token}:
            match (Sessions.user(token)) {
              case {some: user}: Http.Json.success({success: user})
              case {none}:       Http.Json.success({failure: "No meta user for token"})
            }
          case {none}:
            Http.Json.success({failure: "No token in OAuth parameters"})
        }
      })
    }

    function logout(int version) {
      check_versions(version, 0, "1.0", function (params) {
        debug("oauth logout")
        match (List.assoc("oauth_token", params)) {
          case {some:token}:
            Sessions.delete(token)
            Http.Json.success({success: "Successfully logged out"})
          case {none}: Http.Json.success({error: "No token in OAuth parameters"})
        }
      })
    }

  } // END OAUTH

  /**
   * Common message operations.
   * (Message, Draft)
   */
  module Common {

    /**
     * Create a response with a subset of the fields of the message set, and status {success}.
     * Shared labels are not included.
     * Fields returned are: id, [threadId,] labelIds.
     */
    function format(status) {
      labelIds =
        (if (status.flags.read) [] else ["UNREAD"]) ++
        (if (status.flags.starred) ["STARRED"] else []) ++
        [Box.identifier(status.mbox)|List.map(Label.sofid, status.labels)]
      Http.Json.success({
        id: status.id,
        // threadId: message.thread,
        ~labelIds
      })
    }

    /**
     * Fetch a draft or a message.
     * Because of a typing failure, two [tranform] arguments are needed instead of one.
     * @param transform transformation of the message data to a resource.
     */
    function get(int _version, Message.id mid, transform_minimal, transform_full) {
      debug("Fetch draft")
      state = Login.get_state()
      url = HttpRequest.get_url()
      format = Http.Query.string("format", url) ? "full" |> Parse.format

      if (not(Login.is_logged(state)))
        Http.Json.unauthorized()
      else {
        outcome = MessageController.get_status(state, mid, format)
        match (outcome) {
          case {success: status}:
            resource = Message.Api.message_to_resource(state.key, status, format)
            match (resource) {
              case {minimal: resource}: transform_minimal(resource)
              case {full: resource}:    transform_full(resource)
              case {failure: msg}: Http.Json.not_found(msg)
            }
          case {failure: msg}: Http.Json.not_found(msg)
        }
      }
    }

    /** Delete a single message or draft. */
    function delete(int _version, Message.id mid, bool draft) {
      debug("Delete message")
      state = Login.get_state()
      outcome = MessageController.delete(state, mid, draft)
      match (outcome) {
        case {success: _}: Http.Json.success({})
        case {failure: err}: Http.Json.not_found(err)
      }
    }

    /**
     * History of the modifications.
     * @param hist fetch recent history
     * @param last return id of the last relevant log entry
     * @param format format log entry into an api exportable object
     */
    function history(int _version, string name, hist, format, last) {
      url = HttpRequest.get_url()
      maxResults = Http.Query.int("maxResults", url) ? 50
      match (Http.Query.string("startHistoryId", url)) {
        case {some: startHistoryId}:
          state = Login.get_state() // Login checked by parser.
          if (not(Login.is_logged(state))) Http.Json.unauthorized()
          else {
            entries = hist(state.key, startHistoryId, maxResults) |> List.map(format, _)
            history = {
              history: entries,
              historyId: last(state.key)
            }
            Http.Json.success(history)
          }
        default:
          warning("{name}: Missing required query parameter 'startHistoryId'")
          Http.Json.bad_request("Missing required query parameter 'startHistoryId'")
      }
    }

  } // END COMMON

  /**
   * Message specific operations.
   */
  module Messages {

    format = Common.format

    /** Fetch a message. */
    @expand function get(int version, Message.id mid) { Common.get(version, mid, Http.Json.success, Http.Json.success) }

    /** Delete a message. */
    @expand function delete(int version, Message.id mid) { Common.delete(version, mid, false) }

    /** List messages. */
    function list(int version) {
      url = HttpRequest.get_url()
      headers = HttpRequest.get_headers()
      state = Login.get_state()
      if (not(Login.is_logged(state)))
        Http.Json.unauthorized()
      else {
        // Ignored.
        includeSpamTrash = Http.Query.bool("includeSpamTrash", url) ? false
        maxResults = Http.Query.int("maxResults", url) ? 50
        // The page token is for now just the id (or date ?) of the last message of the previous page.
        pageToken =
          Http.Query.int("pageToken", url) |>
          Option.map(Date.time_t_of_int, _) |>
          Option.map(Date.ll_import, _)
        pageToken = pageToken ? Date.now()
        // Only one supported at the moment. If none is provided, defaults to inbox.
        box = Http.Query.string("labelIds", url) |> Option.map(Box.iparse, _)
        box = box ? {inbox}
        // Ignored.
        q = Http.Query.string("q", url)
        // Fetch.
        log("Messages.list: user:{state.key} box:{box} pageToken:{pageToken} maxResults:{maxResults}")
        messages = Message.ranged_in_mbox(state.key, box, pageToken, maxResults) |> Iter.to_list
        last = Option.map(_.created, Utils.last_opt(messages)) ? pageToken
        // Build response.
        payload = {
          messages: List.map(function (message) { {id: message.id} }, messages),
          nextPageToken: last,
          resultSizeEstimate: List.length(messages)
        }
        // Return.
        Http.Json.success(payload)
      }
    }

    /**
     * Insert a message provided in raw format.
     * @param send do send the message to external recipients.
     */
    function insert(int version, bool send) {
      url = HttpRequest.get_url()
      headers = HttpRequest.get_headers()
      uploadType = Http.Query.string("uploadType", url) ? "media"
      content_type = Option.bind(_.header_get("Content-Type"), headers)
      content_transfer_encoding = Option.bind(_.header_get("Content-Transfer-Encoding"), headers) ? ""

      // Switch on upload type.
      match ((Parse.upload_type(uploadType), content_type)) {
        /**
         * Media uplaod.
         * Body should be composed of a single part containing the mail information.
         * Content type must be message/rfc822.
         */
        case ({media}, {some: "message/rfc822"}):
          body =
            if (String.lowercase(content_transfer_encoding) == "base64")
              HttpRequest.get_body() |> Option.map(Binary.of_base64, _) |> Option.map(Binary.to_string, _)
            else HttpRequest.get_body()
          t0 = Date.now()
          state = Login.get_state() // OAuth parameters checked here.
          match (Option.bind(SmtpController.parse(some(state.key), _, []), body)) {
            case {some: (message, inline)}:
              t1 = Date.now()
              blength = String.byte_length(message.content)
              if (blength < AppConfig.message_max_size) {
                Message.Async.add(some(state.key), message, inline, false, send, {none}, ignore)


                format(message.status(state.key))
              } else {
                warning("Oversized message body: {blength} > authorized {AppConfig.message_max_size}")
                Http.Json.bad_request("Oversized message body: {blength} > authorized {AppConfig.message_max_size}")
              }
            default:
              warning("Corrupt mime content")
              Http.Json.bad_request("Corrupt mime content")
          }

        /**
         * Multipart upload.
         * Body should be composed of two part, one containg the message and files metadata,
         * the other being the raw message.
         * Mime content type is:
         *  - multipart/related for the first part
         *  - application/json for the metadata
         *  - message/rfc822 for the raw message
         */
        case ({multipart}, {some: "application/json"}):
          body = HttpRequest.get_body()
          match (Option.bind(Mime.parse, body)) {
            case {some:
             ~{ raw,
                content: {
                  headers: top_headers,
                  body: { multipart: [
                    { headers: metadata_headers, body: {plain: metadata} },
                    { headers: message_headers, body: {multipart: [message]}  }
                  ]}
                }
              }
            }:
              metadata_type = Mime.Header.find("Content-Type", metadata_headers) |> Option.map(String.to_lower, _)
              content_type = Mime.Header.find("Content-Type", top_headers) |> Option.map(String.to_lower, _)
              message_type = Mime.Header.find("Content-Type", message_headers) |> Option.map(String.to_lower, _)
              state = Login.get_state()
              // Check headers.
              if (content_type != {some: "multipart/related"}) {
                log("Expected MIME type multipart/related")
                Http.Json.bad_request("Expected MIME type multipart/related")
              } else if (metadata_type != {some: "application/json"}) {
                log("Expected MIME type application/json")
                Http.Json.bad_request("Expected MIME type application/json")
              } else if (message_type != {some: "message/rfc822"}) {
                log("Expected MIME type rfc/822")
                Http.Json.bad_request("Expected MIME type rfc/822")
              } else {
                default_flags = {
                  seen : true, answered : false, flagged : false,
                  deleted : false, draft : false, recent : false,
                  junk : false
                }
                (message, inline) = SmtpController.message_of_mime(state.key, {raw: raw, content: message}, [], default_flags)
                // TODO: add metadata.
                // metadata = Message.metadata_of_mime(metadata_headers, metadata.f1, metadata.f2)
                Message.add(some(state.key), message, inline, false, send, {none}) |> ignore
                log("Message insertion successful")
                format(message.status(state.key))
              }
            default: Http.Json.bad_request("Malformed message")
          }

        /**
         * Resumable uploads.
         * UNSUPPORTED
         */
        case ({resumable}, _):
          /** Resumable uploads not supported for the moment. */
          warning("Unsupported upload type 'resumable'")
          Http.Json.not_supported(version)

        /** Unsupported parameters. */
        case (_, {some: ct}):
          warning("Unsupported content type '{ct}'")
          Http.Json.bad_request("Unsupported content type '{ct}'")
        case (_, {none}):
          warning("Undefined content type")
          Http.Json.bad_request("Undefined content type")
      }
    }

    /**
     * Modify the mail box and flags of a message.
     * If successful, return a resource with {id, threadId, labelIds}.
     * Else, return an error.
     */
    function modify(int version, Message.id mid) {
      debug("Message.modify")
      body = HttpRequest.get_json_body()
      addLabelIds = []
      removeLabelIds = []
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: ~{addLabelIds, removeLabelIds}}
        case {some: ~{addLabelIds}}
        case {some: ~{removeLabelIds}}:
          state = Login.get_state()
          // Remove void labels.
          (add, remove) =
            ( List.filter(function (lbl) { not(List.mem(lbl, removeLabelIds)) }, addLabelIds),
              List.filter(function (lbl) { not(List.mem(lbl, addLabelIds)) }, removeLabelIds) )
          // Categorize involved labels.
          remove = Folder.categorize(state.key, remove)
          add = Folder.categorize(state.key, add)
          // Check for parsing errors.
          if (remove.error != [] || add.error != [])
            Http.Json.bad_request({message: "Undefined labels", errors: remove.error ++ add.error})
          else {
            // Apply status labels: unread, starred.
            if (remove.starred) MessageController.star(state, mid, false) |> ignore
            if (add.starred) MessageController.star(state, mid, true) |> ignore
            if (remove.unread) MessageController.read(state, mid, true) |> ignore
            if (add.unread) MessageController.read(state, mid, false) |> ignore
            // Apply label changes.
            outcome = MessageController.update_labels(mid, add.labels, remove.labels)
            match (outcome) {
              case {success: (header, status)}:
                // Apply folder changes.
                move = (add.folders, remove.folders)
                match (move) {
                  case ([], []): format(status)
                  case ([to],[from]):
                    outcome = MessageController.move(state, mid, from, to)
                    match (outcome) {
                      case {success: message}: format(message)
                      case ~{failure}:
                        warning("Message.modify: folder update failed with add={add.folders} remove={remove.folders}")
                        Http.Json.not_found(failure)
                    }
                  default:
                    warning("Message.modify: folder update failed with add={add.folders} remove={remove.folders}")
                    Http.Json.bad_request("Bad folder update")
                }
              case ~{failure}:
                warning("Message.modify: label update failed with add={add.labels} remove={remove.labels}")
                Http.Json.bad_request(failure)
            }
          }
        default:
          Http.Json.not_found("Malformed body")
      }
    }

    /**
     * Trash / Untrash a message.
     *
     * If operation is successful, return a resource with {id, threadId, labelIds} (in json format).
     * Else, return an error.
     */
    function trash(int _version, Message.id mid) {
      debug("Trash message")
      state = Login.get_state()
      match (MessageController.trash(state, mid)) {
        case {success: message}: format(message)
        case {failure: msg}: Http.Json.not_found(msg)
      }
    }
    function untrash(int _version, Message.id mid) {
      debug("Untrash message")
      state = Login.get_state()
      match (MessageController.untrash(state, mid)) {
        case {success: message}: format(message)
        case {failure: msg}: Http.Json.not_found(msg)
      }
    }

    /** History of the modifications. */
    module History {
      /** List all the modifications reported in the hisotry since the last given update. */
      function list(int _version) {
        url = HttpRequest.get_url()
        labelId = Http.Query.string("labelId", url)
        maxResults = Http.Query.int("maxResults", url) ? 50
        pageToken = Http.Query.int("pageToken", url) ? 1
        match (Http.Query.string("startHistoryId", url)) {
          case {some: startHistoryId}:
            state = Login.get_state() // Login checked by parser.
            entries =
              Journal.Message.history(state.key, startHistoryId, maxResults, labelId) |>
              List.map(function (entry) {{
                messages: [{messageId: entry.mid}], // FIXME: bad json serialization that results in hd; tl?
                id: entry.id
              }}, _)
            history = {
              history: entries,
              historyId: Journal.Message.last(state.key)
              // nexPageToken: ""
            }
            Http.Json.success(history)
          default:
            Http.Json.bad_request("Missing required query parameter 'startHistoryId'")
        }
      }
    } // END HISTORY

  } // END MESSAGE

  /**
   * Draft specific operations.
   */
  module Drafts {

    format = Common.format

    /** Fetch a draft. */
    @expand function get(int version, Message.id mid) {
      Common.get(
        version, mid,
        function (json) { Http.Json.success({id: mid, message: json}) },
        function (json) { Http.Json.success({id: mid, message: json}) })
    }

    /** Delete a draft. */
    @expand function delete(int version, Message.id mid) { Common.delete(version, mid, true) }

    /**
     * Send a draft.
     * If successful, a partial message is returned, with the fields {id, threadId, labelIds}.
     */
    function send(int _version) {
      debug("Send draft")
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: ~{id}}:
          state = Login.get_state()
          mid = Message.midofs(id)
          if (not(Login.is_logged(state))) Http.Json.unauthorized()
          else
            match (MessageController.send_draft(state, mid)) {
              case {success: (message, _encrypted)}: format(message)
              case {failure: msg}: Http.Json.not_found(msg)
            }
        default:
          Http.Json.not_found(AppText.Draft_not_found())
      }
    }

  } // END DRAFT

  module Attachments {
    function get(int _version, Message.id mid, File.id fid) {
      // Login checked by getAttachment.
      debug("Attachments.get: verion={_version} MID={mid} FID={fid}")
      FileController.Expose.getAttachment(mid, fid) |> Http.Json.outcome
    }
  } // END ATTACHMENTS

  /**
   * Folder specific operations.
   */
  module Folders {

    private make_response = function {
      case {success: result}: Http.Json.success(result)
      case {failure: msg}:
        warning("Failed to perform the required operation")
        Http.Json.bad_request(msg)
    }

    /** Combines the {create}, {modify} functions.
     * TODO: implement patch semantics for updates.
     */
    function save(version, option(Folder.id) id) { Http.Json.not_supported(version) }
    function delete(version, id) { Http.Json.not_supported(version) }
    function get(version, id) { Http.Json.not_supported(version) }
    function list(version) { Http.Json.not_supported(version) }
    function patch(version, id) { Http.Json.not_supported(version) }

  } // END FOLDERS

  /** Tags: joint labels and folders queries. */

  module Tags {

    private function logged(response) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) Http.Json.unauthorized()
      else response(state)
    }

    function get(_version, id) { logged(Tag.Api.get(_, id)) }
    function list(_version) { logged(Tag.Api.list) }
    function save(_version, option(string) id) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: params}: logged(Tag.Api.save(_, id, params))
        default: Http.Json.bad_request("Missing folder name")
      }
    }

    function delete(version, id) { Http.Json.not_supported(version) }
    function patch(version, id) { Http.Json.not_supported(version) }

  } // END TAGS

  /**
   * User methods.
   * Except for the {list} method, arguments will be passed inside of a json
   * value, in the body. For the {list} methodn query parameters will be used instead.
   */
  module Users {

    /** Fetch a single user. */
    function get(_version, User.key key) {
      url = HttpRequest.get_url()
      format = Http.Query.string("format", url) ? "full" |> Parse.format
      match (UserController.get(key, format)) {
        case {success: {full: user}}: Http.Json.success(user)
        case {success: {minimal: user}}: Http.Json.success(user)
        case ~{failure}: Http.Json.outcome(~{failure})
      }
    }

    /**
     * Run a query on the list of users.
     * Search parameters are passed as query parameters:
     *  - teamKeys: return only users belonging to EACH of the teams
     *  - maxResults: limiit the number of results (default 50)
     *  - q: additional query string
     *  - pageToken: key of the last user of the previous page.
     */
    protected function list(version) {
      url = HttpRequest.get_url()
      teamKeys = Http.Query.stringlist("teamKeys", url)
      maxResults = Http.Query.int("maxResults", url) ? 50
      pageToken = Http.Query.string("pageToken", url)
      q = Http.Query.string("q", url)
      // Always successful, but result may be empty.
      Http.Json.success(UserController.list(pageToken, teamKeys, maxResults))
    }

    function insert(_version) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: data}:
          // status = parse_status(data.status)
          fname = data.firstName
          lname = data.lastName
          match (AdminController.register(fname, lname, data.username, data.password, data.level, data.teams)) {
            case {success: (_, user)}: Http.Json.success(user)
            case ~{failure}: Http.Json.outcome(~{failure})
          }
        default:
          warning("Users.insert: Malformed body and/or missing fields")
          Http.Json.bad_request("Malformed body and/or missing fields")
      }
    }

    function update(_version, User.key key) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: data}:
          status = Parse.status(data.status)
          UserController.save(key, data.level, status) |> Http.Json.outcome
        default:
          warning("Users.update: Malformed body and/or missing fields")
          Http.Json.bad_request("Malformed body and/or missing fields")
      }
    }


    /**
     * Manage user teams.
     * The request body must contain a json value with two fields:
     *  - addedTeamKeys
     *  - removedTeamKeys
     */
    function move(_version, User.key key) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: ~{addedTeamKeys, removedTeamKeys}}:
          UserController.update_teams(key, {removed_teams: removedTeamKeys, added_teams: addedTeamKeys}) |> Http.Json.outcome
        default:
          warning("Users.move: Malformed body and/or missing fields")
          Http.Json.bad_request("Malformed body and/or missing fields")
      }
    }

    /** Delete a user. */
    function delete(_version, User.key key) {
      UserController.Expose.delete(key) |> Http.Json.outcome
    }

    /** History of the modifications. */
    function history(_version) {
      hist = Journal.Admin.history(_, _, _, {user})
      function format(entry) {{ userKey: entry.src, id: entry.id }}
      last = Journal.Admin.last
      Common.history(_version, "Teams.history", hist, format, last)
    }

  } // END USERS

  /** Team methods. */
  module Teams {

    /** Fetch a single team. */
    function get(_version, Team.key key) {
      TeamController.get(key) |> Http.Json.outcome
    }

    /** Return the full list of administrated teams. */
    function list(_version) { Http.Json.success(TeamController.list()) }

    /** Create a new team. */
    function insert(_version) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: (Team.insert data)}:
          TeamController.save(none, data.parent, data.name, data.description) |> Http.Json.outcome
        default:
          warning("Teams.insert: Malformed body and/or missing fields")
          Http.Json.bad_request("Malformed body and/or missing fields")
      }
    }

    /** Update an existing team. */
    function update(_version, Team.key key) {
      body = HttpRequest.get_json_body()
      match (Option.bind(OpaSerialize.Json.unserialize_unsorted, body)) {
        case {some: (Team.update data)}:
          TeamController.save(some(key), none, data.name, data.description) |> Http.Json.outcome
        default:
          warning("Teams.update: Malformed body and/or missing fields")
          Http.Json.bad_request("Malformed body and/or missing fields")
      }
    }

    /** Delete a team. */
    function delete(_version, Team.key key) {
      TeamController.delete(key) |> Http.Json.outcome
    }

    /** History of the modifications. */
    function history(_version) {
      hist = Journal.Admin.history(_, _, _, {team})
      function format(entry) {{ teamKey: entry.src, id: entry.id }}
      last = Journal.Admin.last
      Common.history(_version, "Teams.history", hist, format, last)
    }

  } // END TEAMS

  /**
   * File and directory operations.
   * As in URNs, the files submode determines where the path is pointing to.
   * As a rule, all paths should start with the submode, as in [team/../path/to/file]. If unrecognised,
   * the submode defaults to 'files', which identifies the regular file system.
   * The {root} parameter that should be inserted in all queries is not used.
   */
  module FS {

    /** Extract the source file or directory represented by the provided path. */
    private function source(string path) {
      match (Path.parse(path)) {
        case [mode|path]:
          state = Login.get_state()
          urn = {mode: {files: mode}, ~path}
          src = FSController.get_source(state, urn)
          match (src) {
            case {success: src}: {success: (src, state)}
            case ~{failure}: ~{failure}
          }
        default: Utils.failure("", {wrong_address})
      }
    }

    /**
     * Return the file content, as well as the file the metadata
     * (placed in the x-webmail-metadata header)/
     */
    function get(int _version, string path) {
      match (source(path)) {
        case {success: (src, state)}:
          match (FSController.Api.download(state.key, src, true, true)) {
            case {success: (content, mimetype, name, metadata)}:
              Resource.binary(content, mimetype) |>
              Resource.add_header(_, {content_disposition : {attachment : name}}) |>
              Resource.add_header(_, {custom: ("X-Webmail-Metadata", OpaSerialize.serialize(metadata))})
            case {failure: err}: Http.Json.error(err)
          }
        case {failure: err}: Http.Json.error(err)
      }
    }

    function metadata(int _version, string path) {
      match (source(path)) {
        case {success: (src, state)}:
          url = HttpRequest.get_url()
          list = Http.Query.bool("list", url) ? false
          file_limit = Http.Query.int("file_limit", url) ? 10000
          match (FSController.Api.metadata(state.key, src, list, true)) {
            case {success: metadata}: Http.Json.success(metadata)
            case {failure: err}: Http.Json.error(err)
          }
        case {failure: err}: Http.Json.error(err)
      }
    }

    function upload(int _version, string path) {
      url = HttpRequest.get_url()
      headers = HttpRequest.get_headers()
      // Extract parameters.
      overwrite = Http.Query.bool("overwrite", url) ? false
      parent_rev = Http.Query.string("parent_rev", url)
      autorename = Http.Query.bool("autorename", url) ? true
      class = Label.open.id
      mimetype = Option.bind(_.header_get("Content-Type"), headers) ? "application/octet-stream"
      log("File upload: {path}")
      // Extract body.
      content_transfer_encoding = Option.bind(_.header_get("Content-Transfer-Encoding"), headers) ? ""
      data =
        if (String.lowercase(content_transfer_encoding) == "base64")
          HttpRequest.get_body() |> Option.map(Binary.of_base64, _)
        else HttpRequest.get_bin_body()
      // Identify the place of destination.
      path = Path.parse(path)
      match (FileTokenController.Api.upload(data ? Binary.create(0), mimetype, class, path)) {
        case {success: token}:
          Http.Json.success({})
        case {failure: err}: Http.Json.error(err)
      }
    }

    /** Folder creation. */
    function create(int version) { Http.Json.not_supported(version) }

    /**
     * Note about the parameters: the 'root' parameter, which is used by dropbox to specify the root directory,
     * take different values here, more suitable to identify shared folders and paths.
     * At least three values are accepted:
     *  - 'team': refer to team folders
     *  - 'file' (or anything else): regular file system
     *  - 'share' to public links (only accessible in read mode)
     *
     * FIXME: copy is not supported at the moment.
     */
    function move(int _version, bool copy) {
      url = HttpRequest.get_url()
      from_path = Http.Query.string("from_path", url)
      to_path = Http.Query.string("to_path", url)
      root = Http.Query.string("root", url) ? ""
      match ((from_path, to_path)) {
        case ({some: from_path}, {some: to_path}):
          from_path = Path.parse(from_path)
          to_path = Path.parse(to_path)
          match (FSController.Api.move(root, from_path, to_path, copy)) {
            case {success: s}: Http.Json.success(s)
            case ~{failure}: Http.Json.error(failure)
          }
        default:
          warning("FS.move({copy}): Missing required query parameters")
          Http.Json.bad_request("Missing required query parameters")
      }
    }

    function delete(int _version) {
      url = HttpRequest.get_url()
      path = Http.Query.string("path", url)
      root = Http.Query.string("root", url) ? ""
      match (path) {
        case {some: path}:
          path = Path.parse(path)
          match (FSController.Api.delete(root, path)) {
            case {success: s}: Http.Json.success(s)
            case {failure: err}: Http.Json.error(err)
          }
        default:
          warning("FS.delete: Missing required query parameters")
          Http.Json.bad_request("Missing required query parameters")
      }
    }

  } // END FS

}
