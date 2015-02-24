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


package com.mlstate.webmail.tools

import-plugin server

/** Type of errors returned by API methods. */
type API.error('a) = {web_response code, 'a data}

private launch_time = Date.in_milliseconds(Server_private.launch_date)

function `<|`(f, a) { f(a) }
function dollar(s) { Dom.select_raw_unsafe(s) }

module Utils {

  /** Check a subdomain. */
  function issubdomain(string sub) {
    // Cannot limit number of repeats, so we must check length manually.
    charok = Parser.parse(parser {
      case [a-zA-Z0-9] (!(. Rule.eos) [a-zA-Z0-9\-])+ [a-zA-Z0-9] : true
      default: false
    }, sub)
    if (charok) String.length(sub) < 64
    else false
  }

  /** Check domain TLD. */
  function isTLD(string tld) {
    Parser.parse(parser {
      case [a-zA-Z] [a-zA-Z]+: true
      default: false
    }, tld)
  }

  /** Check whether the string represents a valid domain name. */
  function isdomain(string dom) {
    if (String.has_prefix(".", dom) ||
      String.has_suffix(".", dom)) false
    else {
      subdomains = String.explode_with(".", dom, false) |> List.rev
      match (subdomains) {
        case [ext|subs]:
          isTLD(ext) && List.for_all(issubdomain, subs)
        default: false
      }
    }
  }

  function auto_version(string url) { "{url}?v={launch_time}" }
  function make_ext_link_w_title(url, title, content) { <a href="{url}" title="{title}" target="_blank">{content}</a> }
  function make_ext_link(url, content) { <a href="{url}" target="_blank">{content}</a> }

  /** Alias function read file. */
  function readFile(path) { File.read(path) }

  /** Compute the duration in ms between two dates. */
  function delta(a, b) { Duration.between(a, b) |> Duration.in_milliseconds }

  /** Create an image data url. */
  function dataUrl(picture) {
    data = Binary.to_base64(picture.data)
    "data:{picture.mimetype};base64,{data}"
  }

  /** Sanitize an input string: trim whitespaces and convert to lower case. */
  function sanitize(string input) { String.lowercase(String.trim(input)) }

  /** Conversion functions between option(string), list(string) and string. */
  function lofs(string s) { if (s == "") [] else [s] }
  function sofl(list(string) l) { match (l) { case [s|_]: s ; default: "" } }
  function oofs(string s) { if (s == "") none else some(s) }
  function sofo(option(string) o) { o ? "" }
  function lofo(option('a) o) { match (o) { case {some: e}: [e] ; default: [] } }

  /** Constant function. */
  @expand function const(c)(_) { c }
  /** Dummy event handler. */
  client function voidaction(_evt) { void }

  /**
   * Remove the last element of the list.
   * (Different from List.init)
   */
  function init(list('a) xs) {
    recursive function aux(xs, acc) {
      match (xs) {
        case [] case [_]: List.rev(acc)
        case [x|xs]: aux(xs, [x|acc])
      }
    }
    aux(xs, [])
  }

  /** Return the last element of the given list. */
  function last(list('a) xs) {
    match (xs) {
      case []: error(@i18n("empty list in function 'last'"))
      case [x]: x
      case [_|xs]: last(xs)
    }
  }

  function last_opt(list('a) xs) {
    match (xs) {
      case []: none
      case [x]: some(x)
      case [_|xs]: last_opt(xs)
    }
  }

  /** Return the last element of the given iterator. */
  function iter_last(iter('a) iter) {
    match (iter.next()) {
      case {some: (elt, iter)}:
        match (iter_last(iter)) {
          case {none}
          case {some: elt}: {some: elt}
        }
      default: none
    }
  }

  /**
   * The two given lists obey the relation 'prefixOf', then return the
   * list with the prefix dropped, else the full list.
   */
  function drop_prefix(xs, ys) {
    recursive function drop(xs, zs) {
      match ((xs, zs)) {
        case ([], zs): zs
        case (_, []): ys
        case ([x|xs], [z|zs]):
          if (x == z) drop(xs, zs) else ys
      }
    }
    drop(xs, ys)
  }

  /** Make a text snippet. */
  function snippet(string text, int maxlen) {
    textlen = String.length(text)
    // Trim spaces.
    recursive function trim(offset, len, acc) {
      if (offset >= textlen || len >= maxlen) String.concat(" ", List.rev(acc))
      else if (String.get(offset, text) |> String.is_blank) trim(offset+1, len, acc)
      else block(offset, offset+1, len+2, acc)
    }
    // Parse text block.
    and function block(offset, index, len, acc) {
      if (index >= textlen || len >= maxlen) {
        b = String.substring(offset, index-offset, text)
        String.concat(" ", List.rev([b|acc]))
      }else if (String.get(index, text) |> String.is_blank) {
        b = String.substring(offset, index-offset, text)
        trim(index+1, len, [b|acc])
      }else
        block(offset, index+1, len+1, acc)
    }
    // Build snippet.
    trim(0, -1, [])
  }

  function string_limit(limit, src) {
    ll = String.length(src)
    if (ll > limit)
      "{String.sub(0, (limit-3), src)}..."
    else src
  }

  function string_limit_opt(limit, src) {
    match (limit) {
      case {some: limit}: string_limit(limit, src)
      default: src
    }
  }

  /** Build a page from a list of data. */
  function page(elts, ref, defref) {
    size = List.length(elts)
    first = Option.map(ref, List.head_opt(elts)) ? defref
    last = Option.map(ref, last_opt(elts)) ? defref
    ~{size, more: true, first, last, elts}
  }

  /**
   * Build a standard failure outcome, that can also be used to build
   * API error responses (using the web response code).
   * TODO: all controller functions should use this function
   * to format their responses.
   */
  @expand both function failure(string message, web_response code) {
    {failure: ~{message, code}}
  }
  /** Standard failures. */
  module Failure {
    @expand function login() { failure(@i18n("Log-in please"), {unauthorized}) }
    @expand function notfound() { failure(@i18n("Non-existent resource"), {wrong_address}) }
    @expand function forbidden() { failure(@i18n("Unauthorized"), {unauthorized}) }
  } // END FAILURE


  function print_size(int size) {
    if (size < 1024) @i18n("{size} bytes")
    else if (size < 1024*1024) @i18n("{size/1024} kB")
    else @i18n("{size/(1024*1024)} MB")
  }

  client function client_transform(f, d, h) { f(d, Dom.of_xhtml(h)) }

  // escape_html(s:string) =
  //   s |> Xhtml.escape_special_chars(_)

  function print_reply(string content) {
    String.explode_with("\n", content, false) |>
    List.fold(function (line, acc) {
      "{acc}\n> {line}"
    }, _, "")
  }

  // unsafe_js_event(event, action) =
  //   {name=event value={value=action}}

  function row(xhtml) { <div class="row">{xhtml}</div> }
  function span6(xhtml) { <div class="col-md-6">{xhtml}</div> }

  function panel_default(xhtml) { <div class="panel panel-default">{xhtml}</div> }
  function panel_heading(xhtml) { <div class="panel-heading">{xhtml}</div> }
  function panel_body(xhtml) { <div class="panel-body">{xhtml}</div> }

  function bool ask(string _title, string message) { Client.confirm(message) }

  // generic_order(a, b) = if a == b then {eq} else {gt}

  function data_loading_text(text, x) { Xhtml.add_attribute_unsafe("data-loading-text", text, x) }
  function data_complete_text(text, x) { Xhtml.add_attribute_unsafe("data-complete-text", text, x) }

  function data_value(v, x) { Xhtml.add_attribute_unsafe("data-value", v, x) }
  function data_type(t, x) { Xhtml.add_attribute_unsafe("data-type", t, x) }
  function data_sort_initial(i, x) { Xhtml.add_attribute_unsafe("data-sort-initial", i, x) }
  function data_sort_ignore(x) { Xhtml.add_attribute_unsafe("data-sort-ignore", "true", x) }

  /** Build a link for responsive file and directory actions menu */
  function text_link(class, link, text) {
    <li>
      <a onclick={link}><span class="fa fa-{class}"/> {text}</a>
    </li>
  }
  function icon_link(class, link, text) {
    <a class="btn btn-icon fa fa-{class}" onclick={link} title="{text}" rel="tooltip" data-placement="bottom"/>
  }

  // http://tools.ietf.org/html/rfc4648#section-5

  base64_url_char = parser { case v=([a-zA-Z0-9\-_%]): Text.to_string(v) }
  base64_url_string = parser { case v=(base64_url_char+): Text.to_string(v) }

  function base64_url_encode(x) {
    String.replace("+", "-", x)
    |> String.replace("/", "_", _)
  }

  function base64_url_decode(x) {
    String.replace("-", "+", x)
    |> String.replace("_", "/", _)
  }

  protected ssl = SSL.make_secure_type({none},{none})

} // END UTILS

/** Url encoding / decoding. */
module UrlEncoding {
  // Because Solr treats "abc%20def" as a single word we can't just use encode_uri.
  // Here, we only encode 8-bit integers (character codes) which are greater than 127.
  // This array is probably the fastest way of doing that in native Opa.
  i2ca = @llarray(
    "\000", "\001", "\002", "\003", "\004", "\005", "\006", "\007", "\008", "\009",
    "\010", "\011", "\012", "\013", "\014", "\015", "\016", "\017", "\018", "\019",
    "\020", "\021", "\022", "\023", "\024", "\025", "\026", "\027", "\028", "\029",
    "\030", "\031", "\032", "\033", "\034", "\035", "\036", "\037", "\038", "\039",
    "\040", "\041", "\042", "\043", "\044", "\045", "\046", "\047", "\048", "\049",
    "\050", "\051", "\052", "\053", "\054", "\055", "\056", "\057", "\058", "\059",
    "\060", "\061", "\062", "\063", "\064", "\065", "\066", "\067", "\068", "\069",
    "\070", "\071", "\072", "\073", "\074", "\075", "\076", "\077", "\078", "\079",
    "\080", "\081", "\082", "\083", "\084", "\085", "\086", "\087", "\088", "\089",
    "\090", "\091", "\092", "\093", "\094", "\095", "\096", "\097", "\098", "\099",
    "\100", "\101", "\102", "\103", "\104", "\105", "\106", "\107", "\108", "\109",
    "\110", "\111", "\112", "\113", "\114", "\115", "\116", "\117", "\118", "\119",
    "\120", "\121", "\122", "\123", "\124", "\125", "\126", "\127",
    "%80", "%81", "%82", "%83", "%84", "%85", "%86", "%87", "%88", "%89", "%8A", "%8B", "%8C", "%8D", "%8E", "%8F",
    "%90", "%91", "%92", "%93", "%94", "%95", "%96", "%97", "%98", "%99", "%9A", "%9B", "%9C", "%9D", "%9E", "%9F",
    "%A0", "%A1", "%A2", "%A3", "%A4", "%A5", "%A6", "%A7", "%A8", "%A9", "%AA", "%AB", "%AC", "%AD", "%AE", "%AF",
    "%B0", "%B1", "%B2", "%B3", "%B4", "%B5", "%B6", "%B7", "%B8", "%B9", "%BA", "%BB", "%BC", "%BD", "%BE", "%BF",
    "%C0", "%C1", "%C2", "%C3", "%C4", "%C5", "%C6", "%C7", "%C8", "%C9", "%CA", "%CB", "%CC", "%CD", "%CE", "%CF",
    "%D0", "%D1", "%D2", "%D3", "%D4", "%D5", "%D6", "%D7", "%D8", "%D9", "%DA", "%DB", "%DC", "%DD", "%DE", "%DF",
    "%E0", "%E1", "%E2", "%E3", "%E4", "%E5", "%E6", "%E7", "%E8", "%E9", "%EA", "%EB", "%EC", "%ED", "%EE", "%EF",
    "%F0", "%F1", "%F2", "%F3", "%F4", "%F5", "%F6", "%F7", "%F8", "%F9", "%FA", "%FB", "%FC", "%FD", "%FE", "%FF"
  )
  function i2c(int i) { LowLevelArray.get(i2ca,i) }

  // This function encodes utf-8 sequences, eg. U+2020 <dagger> -> %E2%80%A0
  function u2c(int u) {
    if (u < 0x100)
      i2c(u)
    else {
      b = Binary.create(4)
      Binary.add_unicode(b, u)
      len = Binary.length(b)
      recursive function aux(i, s) {
        if (i >= len)
          s
        else {
          ch = Binary.get_uint8(b, i)
          aux(i+1,s^"%{Int.to_hex(ch)}")
        }
      }
      aux(0, "")
    }
  }

  function string encode(string str) {
    slen = String.length(str)
    eb = Binary.create(slen*3)
    recursive function aux(i) {
      if (i >= slen)
        Binary.to_binary(eb)
      else {
        cha = %%BslPervasives.char_code_at%%(str, i)
        Binary.add_string(eb, u2c(cha))
        aux(i+1)
      }
    }
    aux(0)
  }

  // We have to perform the reverse for decode, ie. U+2021: %E2%80%A1 -> DOUBLE DAGGER
  c2ia = @llarray(
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
   0,  1,  2,  3,  4,  5,  6,  7,  8,  9, -1, -1, -1, -1, -1, -1,
  -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, 10, 11, 12, 13, 14, 15, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1
  )
  function c2i(int i) { LowLevelArray.get(c2ia,i) }

  // Note that if we stick the 8-bit bytes in the buffer (eg. <e2 80 a1>) they get
  // converted to utf-8 by Binary.to_string.
  function string decode(string str) {
    b = Binary.of_binary(str)
    blen = Binary.length(b)
    eb = Binary.create(blen)
    recursive function aux(i) {
      if (i >= blen)
        Binary.to_binary(eb)
      else {
        ch = Binary.get_string(b, i, 1)
        if (ch == "%") {
          if (i < blen+2) {
            match ((c2i(Binary.get_uint8(b, i+1)),c2i(Binary.get_uint8(b, i+2)))) {
            case (-1,_) case (_,-1):
              Binary.add_string(eb, "%")
              aux(i+1)
            case (h,l):
              Binary.add_uint8(eb, h*16+l)
              aux(i+3)
            }
          } else {
            Binary.add_string(eb, "%")
            aux(i+1)
          }
        } else {
          Binary.add_string(eb, ch)
          aux(i+1)
        }
      }
    }
    aux(0)
  }

} // END URL

/** Checkbox helpers. */
module Checkbox {

  function make(string id, string label, bool checked, bool displayed) {
    input =
      if (checked) <input type="checkbox" id="{id}" checked="checked"/>
      else (<input type="checkbox" id="{id}"/>)
    style = if (displayed) "" else "display:none;"
    <div id="{id}_group" class="form-group" style="{style}">
      {input}
      <label for="{id}">{label}</label>
    </div>
  }

} // END CHECKBOX

type Radio.input = {
  string id,
  string value,
  bool checked,
  xhtml text,
  option(Dom.event -> void) onclick
}

module Radio {

  /** Build the dom element. */
  private function format(Radio.input input, string name) {
    html =
      match ((input.onclick, input.checked)) {
        case ({some: onclick}, {true}): <input type="radio" id="{input.id}" name={name} value="{input.value}" checked="checked" onclick={onclick}></input>
        case ({some: onclick}, {false}): <input type="radio" id="{input.id}" name={name} value="{input.value}" onclick={onclick}></input>
        case ({none}, {true}): <input type="radio" id="{input.id}" name={name} value="{input.value}" checked="checked"></input>
        case ({none}, {false}): <input type="radio" id="{input.id}" name={name} value="{input.value}"></input>
      }
    <label class="radio-inline">{html}{input.text}</label>
  }

  function list(list(Radio.input) inputs) {
    name = Dom.fresh_id()
    inputs =
      List.rev_map(format(_, name), inputs) |>
      List.fold(`<+>`, _, <></>)
    <div class="inputs-list">{inputs}</div>
  }

  /**
   * Get the checked element of an input group.
   * @param val the default value.
   */
  function get_checked(ids, val) {
    List.fold(function (id, val) {
      if (Dom.is_checked(id)) Dom.get_value(id)
      else val
    }, ids, val)
  }

} // END RADIO

module ListGroup {

  function make(list, etext) {
    <div class="list-group">{
      if (list == []) <div class="empty-text"><p>{etext}</p></div>
      else <>{List.map(makeItem, list)}</>
    }</div>
  }

  /** Same as make, with a void action attached to each element. */
  function makeVoid(list, etext) {
    List.map(function (x) { (x, ignore) }, list) |> make(_, etext)
  }

  function makeItem((content, onclick)) {
    <a class="list-group-item" onclick={onclick}>{content}</a>
  }

} // END LISTGROUP

