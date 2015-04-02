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



/**
 Old and depreacted search module.
 Use solr_search.opa instead
*/

BasicSearch = {{

  @private
  get_file_name(id: File.id) =
    File.getName(id) ? ""

  @private
  clean_string(str: string) =
    list = ["\n", "\t", "\r", "\""]
    String.fold(
      str, acc -> if List.mem(str, list) then acc ^ " " else acc ^ str
      , str, "")

  @private
  string_of_message(message: Message.header) =
    from = message.from |> Mail.address_to_email(_)
    to = message.to |> List.map(address -> Mail.address_to_email(address), _) |> List.to_string_using("", "", " ", _)
    cc = message.cc |> List.map(address -> Mail.address_to_email(address), _) |> List.to_string_using("", "", " ", _)
    bcc = message.bcc |> List.map(address -> Mail.address_to_email(address), _) |> List.to_string_using("", "", " ", _)
    subject = message.subject
    content = message.content
    file_names = message.files |> List.map(file -> get_file_name(file), _) |> List.to_string_using("", "", " ", _)
    result = "{from} {to} {cc} {bcc} {subject} {content} {file_names}" |> clean_string(_)
    result

  @private
  webmail_index = SearchGen.create_index(DbUtils.name)

  @server_private
  @async
  index(message: Message.header) =
    document = string_of_message(message)
    nb_docs = Message.count()
    key = Int.to_string(message.id)
    SearchGen.index(webmail_index, document, key, nb_docs)

  @server_private
  index_multiple(message: Message.header) =
    document = string_of_message(message)
    nb_docs = Message.count()
    key = Int.to_string(message.id)
    SearchGen.index_multiple(webmail_index, document, key, nb_docs)

  @server_private
  finalize_index() =
    SearchGen.finalize_index(webmail_index)

  @server_private
  search(key: User.key, mbox: Mail.box, query: string) : list(Message.header) =
    if query == "" then []
    else
      // iterator on all messages by key in mbox
      all_by_in = Message.all_in_mbox(key, mbox)
      filter_found(res_list) =
        Iter.fold(message, acc ->
          if List.mem(Int.to_string(message.id), res_list) then [message|acc]
          else acc
        , all_by_in, [])
      res_list = SearchGen.search(webmail_index, query)
      filter_found(res_list)

}}

