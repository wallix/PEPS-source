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



module AppView {

  client function insertStyle(string appname, _evt) {
    dim = Dom.get_size(#content)
    Log.notice("[AppView]", "content dim: {dim}")
    Dom.set_style(#{"iframe_{appname}"}, [
      {height: {px: dim.y_px}}
    ])
  }

  /** Apps are loaded via an iframe inserted into the content. */
  protected function build(Login.state state, string appname, Path.t path) {
    match (App.find(appname)) {
      case {some: app}:
        // Retrieve an access token to pass to the application.
        query = match (SessionController.create()) {
          case {some: token}: "?oauth_token={token}"
          default: ""
        }
        url = "{app.url}/{Path.print(path)}{query}"
        <iframe id="iframe_{appname}" seamless src={url} class="app-iframe" style="border-width:0px; width:100%;" onready={insertStyle(appname,_)}></iframe>
      default:
        <>{@i18n("Non-existant application")}</>
    }
  }

}
