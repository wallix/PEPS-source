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



module Tag {
module Api {

  /** Extract useful information from a complete folder. */
  private @expand function formatFolder(folder) {
    {id: folder.id, name: folder.name, content: folder.content}
  }

  /** Extract useful information from a complete label. */
  private @expand function formatLabel(label) {
    {id: label.id, name: label.name, category: label.category}
  }

  /**
   * Return the label or folder referenced by the identifier.
   * @return a json value which can be either:
   *
   *  - {folder: {id: string, name: string}}
   *  - {label: {id: int, name: string, category: ..}}
   */
  protected function get(Login.state state, string id) {
    fid = Folder.idofs(id)
    match (Folder.get(state.key, fid)) {
      case {some: box}: Http.Json.success({folder: formatFolder(box)})
      default:
        lid = Label.idofs_opt(id)
        match (Option.bind(Label.get, lid)) {
          case {some: label}: Http.Json.success({label: formatLabel(label)})
          default: Http.Json.not_found("Undefined tag {id}")
        }
    }
  }

  /**
   * List personal folders, as well as shared and personal labels.
   * @return a json response of the form:
   *
   *  {folders: [], labels: []}
   */
  protected function list(Login.state state) {
    folders = Folder.list(state.key) |> List.rev_map(formatFolder, _)
    labels = Label.list(state.key, {shared}) |> List.rev_map(formatLabel, _)
    Http.Json.success(~{folders, labels })
  }

  /** Delete a folder or label. */
  protected function delete(Login.state state, string id) {
    fid = Folder.idofs(id)
    lid = Label.idofs_opt(id)
    delbox = FolderController.delete(state, id, {inbox})
    dellabel = Option.map(LabelController.delete(state, _), lid)
    match ((delbox, dellabel)) {
      case ({success}, _)
      case (_, {some: {success}}): Http.Json.success({})
      default: Http.Json.not_found("Could not delete the tag {id}")
    }
  }

  /**
   * Create a folde or label.
   * @param id an optional id. If the id is present, the referenced tag will be updated,
   *  else a new tag will be created.
   * @param params: parameters passed to the update. They must be of the form:
   *     {label: {name: string, category: {personal} or {shared}}}
   *  or {folder: {name: string}}
   */
  protected function save(Login.state state, option(string) id, params) {
    match (params) {
      case {label: ~{name, description, category}}:
        lid = Option.bind(Label.idofs_opt, id)
        match (LabelController.save(state, lid, name, description, category)) {
          case {success: id}: Http.Json.success(~{id})
          case ~{failure}: Http.Json.bad_request(~{failure})
        }
      case {folder: ~{name}}:
        fid = Option.map(Folder.idofs, id)
        match (FolderController.save(state, fid, name)) {
          case {success: id}: Http.Json.success(~{id})
          case ~{failure}: Http.Json.bad_request(~{failure})
        }
    }
  }

} // END API
} // END TAG
