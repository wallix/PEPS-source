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


package com.mlstate.webmail.static

type AppParameters.t = {
  option(string) admin_pass,
  option(string) domain,
  int key_size,
  string solr_addr,
  int solr_port,
  int smtp_in_port,
  option(string) smtp_out_host, // Using direct transport if undefined.
  option(int) smtp_out_port,
  option(int) http_server_port,
  bool no_ssl
}

module AppParameters {

  private AppParameters.t default_params = {
    admin_pass: none,
    domain: none,
    key_size: 512,
    solr_addr: "127.0.0.1",
    solr_port: 8983,
    smtp_in_port: 8999,
    smtp_out_port: none,
    smtp_out_host: none,
    http_server_port: none,
    no_ssl: false
  }

  // smtp_monitor2_addr = Mutable.make("localhost")

  private CommandLine.family(AppParameters.t) parameters_family = {
    title : @intl("Parameters"),
    init : default_params,
    anonymous : [],
    parsers : [
      { CommandLine.default_parser with
        names : [@intl("--set-admin-password")],
        description : @intl("Set the administrator password"),
        param_doc : @intl("<password>"),
        on_param : function(state) { parser { p=(.*) :
          state = { state with admin_pass : some(Text.to_string(p)) }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--set-domain")],
        description : @intl("Set PEPS domain"),
        param_doc : @intl("<domain>"),
        on_param : function(state) { parser { url=(.*) :
          state = { state with domain : some(Text.to_string(url)) }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--smtp-in-port")],
        description : @intl("Set the SMTP in port"),
        param_doc : @intl("<int>"),
        on_param : function(state) { parser { port=Rule.integer :
          state = { state with smtp_in_port: port }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--smtp-out-port")],
        description : @intl("Set the SMTP out port"),
        param_doc : @intl("<int>"),
        on_param : function(state) { parser { port=Rule.integer :
          state = { state with smtp_out_port: some(port) }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--smtp-out-host")],
        description : @intl("Set the SMTP out host"),
        param_doc : @intl("<string>"),
        on_param : function(state) { parser { host=(.*) :
          state = { state with smtp_out_host: some(Text.to_string(host)) }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--set-key-size")],
        description : @intl("Set the RSA key size"),
        param_doc : @intl("<size>"),
        on_param : function(state) { parser { s=(.*) ->
          size = Int.of_string_opt(Text.to_string(s)) ? state.key_size
          state = { state with key_size : size }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--solr-addr")],
        description : @intl("Set the solr server address"),
        param_doc : @intl("<addr>"),
        on_param : function(state) { parser { addr=(.*) :
          state = { state with solr_addr : Text.to_string(addr) }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--solr-port")],
        description : @intl("Set the solr port number"),
        param_doc : @intl("<int>"),
        on_param : function(state) { parser { s=(.*) ->
          port = Int.of_string_opt(Text.to_string(s)) ? state.solr_port
          state = { state with solr_port : port }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--http-server-port")],
        description : @intl("Set the http server port number"),
        param_doc : @intl("<int>"),
        on_param : function(state) { parser { s=(.*) ->
          port = Int.of_string_opt(Text.to_string(s))
          state = { state with http_server_port : port }
          {no_params : state}
        } } },
      { CommandLine.default_parser with
        names : [@intl("--no-ssl")],
        description : @intl("Disable SSL and use HTTP"),
        param_doc : @intl("<boolean>"),
        on_param : function(state) { parser { no_ssl=Rule.bool :
          state = { state with ~no_ssl }
          {no_params : state}
        } } },

    ]
  }

  /** Extract app parameters and import other values. */
  function extract() {
    parameters = CommandLine.filter(parameters_family)

    @catch(
    function (exn) { parameters }, {
      if (File.exists("/etc/peps/domain")) {
        domain = File.read("/etc/peps/domain") |> Binary.to_string |> String.trim
        Log.notice("[Parameters]", "obtained domain from /etc/peps/domain: {domain}")
        {parameters with domain: some(domain)}
      } else parameters
    })
  }

  /** Export app configuration. */
  function config(string name, string provider, string consumer_key, string consumer_secret, int port) {
    Log.notice("[Config]", "Exporting {name}'s configuration")
    File.mkdir("/etc/peps/apps") |> ignore
    dirok = File.exists("/etc/peps/apps/{name}") || File.mkdir("/etc/peps/apps/{name}")
    if (dirok) {
      File.write("/etc/peps/apps/{name}/provider", Binary.of_string(provider))
      File.write("/etc/peps/apps/{name}/consumer_secret", Binary.of_string(consumer_secret))
      File.write("/etc/peps/apps/{name}/consumer_key", Binary.of_string(consumer_key))
      File.write("/etc/peps/apps/{name}/port", Binary.of_string("{port}"))
    } else
      Log.warning("[Config]", "Failed to export {name} configuration")
  }

  protected parameters = extract()

}
