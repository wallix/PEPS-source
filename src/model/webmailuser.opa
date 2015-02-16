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


package com.mlstate.webmail.model

/**
 * Types and functions to handle the webmailUser schema data.
 *
 * @destination public
 * @stabilization work in progress
 **/

type Ldap.webmailUser = {

  // top
  option(string) dn, // always in search replies

  // person
  list(string) sn, // MUST
  list(string) cn, // MUST
  option(string) userPassword,
  option(string) seeAlso,
  option(string) description,

  //organizationalPerson
  list(string) title,
  list(string) x121Address,
  list(string) registeredAddress,
  list(string) destinationIndicator,
  option(string) preferredDeliveryMethod,
  list(string) telexNumber,
  list(string) teletexTerminalIdentifier,
  list(string) telephoneNumber,
  list(string) internationalISDNNumber,
  list(string) facsimileTelephoneNumber,
  list(string) street,
  list(string) postOfficeBox,
  list(string) postalCode,
  list(string) postalAddress,
  list(string) physicalDeliveryOfficeName,
  list(string) ou,
  list(string) st,
  list(string) l,

  // inetOrgPerson
  list(string) audio,
  list(string) businessCategory,
  list(string) carLicense,
  list(string) teamNumber,
  option(string) displayName,
  option(string) employeeNumber,
  list(string) employeeType,
  list(string) givenName,
  list(string) homePhone,
  list(string) homePostalAddress,
  list(string) initials,
  list(string) jpegPhoto,
  list(string) labeledURI,
  list(string) mail,
  list(string) manager,
  list(string) mobile,
  list(string) o,
  list(string) pager,
  list(string) photo,
  list(string) roomNumber,
  list(string) secretary,
  list(string) uid,
  list(string) userCertificate,
  list(string) x500uniqueIdentifier,
  option(string) preferredLanguage,
  list(string) userSMIMECertificate,
  list(string) userPKCS12,

  // webmailUser
  option(string) webmailUserStatus,
  option(int) webmailUserLevel,
  option(string) webmailUserSgn,
  option(string) webmailUserSalt,
  option(bool) webmailUserBlocked,
}

module WebmailUser {

  Ldap.webmailUser default_webmailUser = {

    // top
    dn:{none},

    // person
    sn:[],
    cn:[],
    userPassword:{none},
    seeAlso:{none},
    description:{none},

    //organizationalPerson
    title:[],
    x121Address:[],
    registeredAddress:[],
    destinationIndicator:[],
    preferredDeliveryMethod:{none},
    telexNumber:[],
    teletexTerminalIdentifier:[],
    telephoneNumber:[],
    internationalISDNNumber:[],
    facsimileTelephoneNumber:[],
    street:[],
    postOfficeBox:[],
    postalCode:[],
    postalAddress:[],
    physicalDeliveryOfficeName:[],
    ou:[],
    st:[],
    l:[],

    // inetOrgPerson
    audio:[],
    businessCategory:[],
    carLicense:[],
    teamNumber:[],
    displayName:{none},
    employeeNumber:{none},
    employeeType:[],
    givenName:[],
    homePhone:[],
    homePostalAddress:[],
    initials:[],
    jpegPhoto:[],
    labeledURI:[],
    mail:[],
    manager:[],
    mobile:[],
    o:[],
    pager:[],
    photo:[],
    roomNumber:[],
    secretary:[],
    uid:[],
    userCertificate:[],
    x500uniqueIdentifier:[],
    preferredLanguage:{none},
    userSMIMECertificate:[],
    userPKCS12:[],

    // webmailUser
    webmailUserStatus:{none},
    webmailUserLevel:{none},
    webmailUserSgn:{none},
    webmailUserSalt:{none},
    webmailUserBlocked:{none},
  }

  private function lst(_name, json, rcrd, cur, set) {
    //Ansi.jlog("lst: name=%y{name}%d cur=%m{cur}%d json=%g{json}%d");
    match (json) {
    case {~String}:
      //Ansi.jlog("{name}: %m{String}%d")
      set(rcrd, [String|cur]);
    case {List:l}:
      new =
        List.fold(function (el, new) {
                    match (el) {
                    case {~String}:
                      //Ansi.jlog("{name}: %m{String}%d")
                      [String|new];
                    default: new;
                    }
                  },l,cur)
      set(rcrd,new);
    default:
      //Ansi.jlog("{name}: %rnot string or list%d")
      rcrd;
    }
  }

  private function opts(__name, RPC.Json.json json, Ldap.webmailUser rcrd,
                        option(string) cur, (Ldap.webmailUser, option(string) -> Ldap.webmailUser) set) { // ie. SINGLE-VALUE
    //Ansi.jlog("opts: name=%y{__name}%d cur=%m{cur}%d json=%g{json}%d");
    function chk(string String) { match (cur) { case {none}: {ok:set(rcrd, {some:String})}; case {some:_}: {multiple}; } }
    match (json) {
    case {~String}: chk(String);
    case {~Int}: chk("{Int}");
    case {~Bool}: chk("{Bool}");
    case {List:[]}: {ok:rcrd};
    case {List:[{~String}]}: chk(String);
    case {List:[{~Int}]}: chk("{Int}");
    case {List:[{~Bool}]}: chk("{Bool}");
    default: {bad:@i18n("Bad JSON for string object {json}")};
    }
  }

  private function opti(__name, RPC.Json.json json, Ldap.webmailUser rcrd, option(int) cur, (Ldap.webmailUser, option(int) -> Ldap.webmailUser) set) { // ie. SINGLE-VALUE
    //Ansi.jlog("opti: name=%y{__name}%d cur=%m{cur}%d json=%g{json}%d");
    function chks(string Int_) {
      match (Int.of_string_opt(Int_)) {
      case {some:Int}:
        match (cur) {
        case {none}: {ok:set(rcrd, {some:Int})};
        case {some:_}: {multiple};
        }
      case {none}: {bad:@i18n("Bad integer string {Int}")};
      }
    }
    function chk(int Int) { match (cur) { case {none}: {ok:set(rcrd, {some:Int})}; case {some:_}: {multiple}; } }
    match (json) {
    case {~String}: chks(String);
    case {~Int}: chk(Int);
    case {List:[]}: {ok:rcrd};
    case {List:[{~String}]}: chks(String);
    case {List:[{~Int}]}: chk(Int);
    default: {bad:@i18n("Bad JSON for int object {json}")};
    }
  }

  private function optb(__name, RPC.Json.json json, Ldap.webmailUser rcrd, option(bool) cur, (Ldap.webmailUser, option(bool) -> Ldap.webmailUser) set) { // ie. SINGLE-VALUE
    //Ansi.jlog("optb: name=%y{__name}%d cur=%m{cur}%d json=%g{json}%d");
    function chks(string Bool) {
      function aux(bool Bool) {
        match (cur) {
        case {none}: {ok:set(rcrd, {some:Bool})};
        case {some:_}: {multiple};
        }
      }
      match (Bool) {
      case "TRUE": aux(true);
      case "FALSE": aux(false);
      default: {bad:@i18n("Bad boolean string {Bool}")};
      }
    }
    function chk(bool Bool) { match (cur) { case {none}: {ok:set(rcrd, {some:Bool})}; case {some:_}: {multiple}; } }
    match (json) {
    case {~String}: chks(String);
    case {~Bool}: chk(Bool);
    case {List:[]}: {ok:rcrd};
    case {List:[{~String}]}: chks(String);
    case {List:[{~Bool}]}: chk(Bool);
    default: {bad:@i18n("Bad JSON for boolean object {json}")};
    }
  }

  private function chkMultiple(aux, flds, res) {
    match (res) {
    case {ok:rcrd}: aux(flds, rcrd);
    case {multiple}: {failure:@i18n("Multiple SINGLE-VALUE entries")};
    case {~bad}: {failure:bad};
    }
  }

  function parseJson(RPC.Json.json json) {
    match (json) {
    case {~Record}:
      recursive function aux(flds, wu) {
        match (flds) {
        case []: {success:wu};
        case [fld|flds]:
          //Ansi.jlog("fld: %b{fld}%d")
          match (String.lowercase(fld.f1)) {

          // top
          case "dn":
            chkMultiple(aux, flds, opts("dn", fld.f2, wu, wu.dn,
                        function (wu, dn) { {wu with ~dn} }));
          case "controls": aux(flds, wu);  // ignore this, it's rarely used

          // person
          case "sn": aux(flds,lst("sn", fld.f2, wu, wu.sn, function (wu, sn) { {wu with ~sn} }));
          case "surname": aux(flds,lst("surname", fld.f2, wu, wu.sn, function (wu, sn) { {wu with ~sn} }));
          case "cn": aux(flds,lst("cn", fld.f2, wu, wu.cn, function (wu, cn) { {wu with ~cn} }));
          case "commonname": aux(flds,lst("commonName", fld.f2, wu, wu.cn, function (wu, cn) { {wu with ~cn} }));
          case "userpassword":
            chkMultiple(aux, flds, opts("userPassword", fld.f2, wu, wu.userPassword,
                        function (wu, userPassword) { {wu with ~userPassword} }));
          case "seealso":
            chkMultiple(aux, flds, opts("seeAlso", fld.f2, wu, wu.seeAlso,
                        function (wu, seeAlso) { {wu with ~seeAlso} }));
          case "description":
            chkMultiple(aux, flds, opts("description", fld.f2, wu, wu.description,
                        function (wu, description) { {wu with ~description} }));

          //organizationalPerson
          case "title":
            aux(flds,lst("title", fld.f2, wu, wu.title,
                function (wu, title) { {wu with ~title} }));
          case "x121address":
            aux(flds,lst("x121Address", fld.f2, wu, wu.x121Address,
                function (wu, x121Address) { {wu with ~x121Address} }));
          case "registeredaddress":
            aux(flds,lst("registeredAddress", fld.f2, wu, wu.registeredAddress,
                function (wu, registeredAddress) { {wu with ~registeredAddress} }));
          case "destinationindicator":
            aux(flds,lst("destinationIndicator", fld.f2, wu, wu.destinationIndicator,
                function (wu, destinationIndicator) { {wu with ~destinationIndicator} }));
          case "preferreddeliverymethod":
            chkMultiple(aux, flds, opts("preferredDeliveryMethod", fld.f2, wu, wu.preferredDeliveryMethod,
              function (wu, preferredDeliveryMethod) { {wu with ~preferredDeliveryMethod} }));
          case "telexnumber":
            aux(flds,lst("telexNumber", fld.f2, wu, wu.telexNumber,
                function (wu, telexNumber) { {wu with ~telexNumber} }));
          case "teletexterminalidentifier":
            aux(flds,lst("teletexTerminalIdentifier", fld.f2, wu, wu.teletexTerminalIdentifier,
                function (wu, teletexTerminalIdentifier) { {wu with ~teletexTerminalIdentifier} }));
          case "telephonenumber":
            aux(flds,lst("telephoneNumber", fld.f2, wu, wu.telephoneNumber,
                function (wu, telephoneNumber) { {wu with ~telephoneNumber} }));
          case "internationalisdnnumber":
            aux(flds,lst("internationalISDNNumber", fld.f2, wu, wu.internationalISDNNumber,
                function (wu, internationalISDNNumber) { {wu with ~internationalISDNNumber} }));
          case "facsimiletelephonenumber":
            aux(flds,lst("facsimileTelephoneNumber", fld.f2, wu, wu.facsimileTelephoneNumber,
                function (wu, facsimileTelephoneNumber) { {wu with ~facsimileTelephoneNumber} }));
          case "street":
            aux(flds,lst("street", fld.f2, wu, wu.street,
                function (wu, street) { {wu with ~street} }));
          case "postofficebox":
            aux(flds,lst("postOfficeBox", fld.f2, wu, wu.postOfficeBox,
                function (wu, postOfficeBox) { {wu with ~postOfficeBox} }));
          case "postalcode":
            aux(flds,lst("postalCode", fld.f2, wu, wu.postalCode,
                function (wu, postalCode) { {wu with ~postalCode} }));
          case "postaladdress":
            aux(flds,lst("postalAddress", fld.f2, wu, wu.postalAddress,
                function (wu, postalAddress) { {wu with ~postalAddress} }));
          case "physicaldeliveryofficename":
            aux(flds,lst("physicalDeliveryOfficeName", fld.f2, wu, wu.physicalDeliveryOfficeName,
                function (wu, physicalDeliveryOfficeName) { {wu with ~physicalDeliveryOfficeName} }));
          case "ou":
            aux(flds,lst("ou", fld.f2, wu, wu.ou,
                function (wu, ou) { {wu with ~ou} }));
          case "st":
            aux(flds,lst("st", fld.f2, wu, wu.st,
                function (wu, st) { {wu with ~st} }));
          case "l":
            aux(flds,lst("l", fld.f2, wu, wu.l,
                function (wu, l) { {wu with ~l} }));

          // inetOrgPerson
          case "audio":
            aux(flds,lst("audio", fld.f2, wu, wu.audio,
                function (wu, audio) { {wu with ~audio} }));
          case "businesscategory":
            aux(flds,lst("businessCategory", fld.f2, wu, wu.businessCategory,
                function (wu, businessCategory) { {wu with ~businessCategory} }));
          case "carlicense":
            aux(flds,lst("carLicense", fld.f2, wu, wu.carLicense,
                function (wu, carLicense) { {wu with ~carLicense} }));
          case "teamnumber":
            aux(flds,lst("teamNumber", fld.f2, wu, wu.teamNumber,
                function (wu, teamNumber) { {wu with ~teamNumber} }));
          case "displayname":
            chkMultiple(aux, flds, opts("displayName", fld.f2, wu, wu.displayName,
                        function (wu, displayName) { {wu with ~displayName} }));
          case "employeenumber":
            chkMultiple(aux, flds, opts("employeeNumber", fld.f2, wu, wu.employeeNumber,
                        function (wu, employeeNumber) { {wu with ~employeeNumber} }));
          case "employeetype":
            aux(flds,lst("employeeType", fld.f2, wu, wu.employeeType,
                function (wu, employeeType) { {wu with ~employeeType} }));
          case "givenname":
            aux(flds,lst("givenName", fld.f2, wu, wu.givenName,
                function (wu, givenName) { {wu with ~givenName} }));
          case "homephone":
            aux(flds,lst("homePhone", fld.f2, wu, wu.homePhone,
                function (wu, homePhone) { {wu with ~homePhone} }));
          case "homepostaladdress":
            aux(flds,lst("homePostalAddress", fld.f2, wu, wu.homePostalAddress,
                function (wu, homePostalAddress) { {wu with ~homePostalAddress} }));
          case "initials":
            aux(flds,lst("initials", fld.f2, wu, wu.initials,
                function (wu, initials) { {wu with ~initials} }));
          case "jpegphoto":
            aux(flds,lst("jpegPhoto", fld.f2, wu, wu.jpegPhoto,
                function (wu, jpegPhoto) { {wu with ~jpegPhoto} }));
          case "labeleduri":
            aux(flds,lst("labeledURI", fld.f2, wu, wu.labeledURI,
                function (wu, labeledURI) { {wu with ~labeledURI} }));
          case "mail":
            aux(flds,lst("mail", fld.f2, wu, wu.mail,
                function (wu, mail) { {wu with ~mail} }));
          case "manager":
            aux(flds,lst("manager", fld.f2, wu, wu.manager,
                function (wu, manager) { {wu with ~manager} }));
          case "mobile":
            aux(flds,lst("mobile", fld.f2, wu, wu.mobile,
                function (wu, mobile) { {wu with ~mobile} }));
          case "o":
            aux(flds,lst("o", fld.f2, wu, wu.o,
                function (wu, o) { {wu with ~o} }));
          case "pager":
            aux(flds,lst("pager", fld.f2, wu, wu.pager,
                function (wu, pager) { {wu with ~pager} }));
          case "photo":
            aux(flds,lst("photo", fld.f2, wu, wu.photo,
                function (wu, photo) { {wu with ~photo} }));
          case "roomnumber":
            aux(flds,lst("roomNumber", fld.f2, wu, wu.roomNumber,
                function (wu, roomNumber) { {wu with ~roomNumber} }));
          case "secretary":
            aux(flds,lst("secretary", fld.f2, wu, wu.secretary,
                function (wu, secretary) { {wu with ~secretary} }));
          case "uid":
            aux(flds,lst("uid", fld.f2, wu, wu.uid,
                function (wu, uid) { {wu with ~uid} }));
          case "usercertificate":
            aux(flds,lst("userCertificate", fld.f2, wu, wu.userCertificate,
                function (wu, userCertificate) { {wu with ~userCertificate} }));
          case "x500uniqueidentifier":
            aux(flds,lst("x500uniqueIdentifier", fld.f2, wu, wu.x500uniqueIdentifier,
                function (wu, x500uniqueIdentifier) { {wu with ~x500uniqueIdentifier} }));
          case "preferredlanguage":
            chkMultiple(aux, flds, opts("preferredLanguage", fld.f2, wu, wu.preferredLanguage,
                        function (wu, preferredLanguage) { {wu with ~preferredLanguage} }));
          case "usersmimecertificate":
            aux(flds,lst("userSMIMECertificate", fld.f2, wu, wu.userSMIMECertificate,
                function (wu, userSMIMECertificate) { {wu with ~userSMIMECertificate} }));
          case "userpkcs12":
            aux(flds,lst("userPKCS12", fld.f2, wu, wu.userPKCS12,
                function (wu, userPKCS12) { {wu with ~userPKCS12} }));

          // webmailUser
          case "webmailuserstatus":
            chkMultiple(aux, flds, opts("webmailUserStatus", fld.f2, wu, wu.webmailUserStatus,
                        function (wu, webmailUserStatus) { {wu with ~webmailUserStatus} }));
          case "webmailuserlevel":
            chkMultiple(aux, flds, opti("webmailUserLevel", fld.f2, wu, wu.webmailUserLevel,
                        function (wu, webmailUserLevel) { {wu with ~webmailUserLevel} }));
          case "webmailusersgn":
            chkMultiple(aux, flds, opts("webmailUserSgn", fld.f2, wu, wu.webmailUserSgn,
                        function (wu, webmailUserSgn) { {wu with ~webmailUserSgn} }));
          case "webmailusersalt":
            chkMultiple(aux, flds, opts("webmailUserSalt", fld.f2, wu, wu.webmailUserSalt,
                        function (wu, webmailUserSalt) { {wu with ~webmailUserSalt} }));
          case "webmailuserblocked":
            chkMultiple(aux, flds, optb("webmailUserBlocked", fld.f2, wu, wu.webmailUserBlocked,
                        function (wu, webmailUserBlocked) { {wu with ~webmailUserBlocked} }));

          default:
            {failure:@i18n("Bad webmailUser field '{fld.f1}'")};
          }
        }
      }
      aux(Record, default_webmailUser);
    default: {failure:@i18n("JSON value is not Record")};
    }
  }

  function outcome(string,string) toJsonString(Ldap.webmailUser wu) {
    missing = List.flatten([if (List.is_empty(wu.cn)) ["cn"] else [],
                            if (List.is_empty(wu.sn)) ["sn"] else []])
    if (not(List.is_empty(missing)))
      {failure:@i18n("Missing MUST fields {String.concat(",",missing)}")}
    else {
      function mkstr(string String) { {~String} }
      function lst(name, l) {
        match (l) {
        case [String]: [(name,{~String})];
        case [_|_]: [(name,{List:List.map(mkstr,l)})];
        case []: [];
        }
      }
      function opts(name, o) { match (o) { case {some:String}: [(name,{~String})]; case {none}: []; } }
      function opti(name, o) { match (o) { case {some:Int}: [(name,{~Int})]; case {none}: []; } }
      function optb(name, o) { match (o) { case {some:Bool}: [(name,{String:if (Bool) "TRUE" else "FALSE"})]; case {none}: []; } }
      {success:
       Json.serialize({Record:List.flatten([

        [// top
         ("objectclass",{List:[{String:"webmailUser"}]})],
         opts("dn",wu.dn),

         // person
         lst("sn",wu.sn),
         lst("cn",wu.cn),
         opts("userPassword",wu.userPassword),
         opts("seeAlso",wu.seeAlso),
         opts("description",wu.description),

         //organizationalPerson
         lst("title",wu.title),
         lst("x121Address",wu.x121Address),
         lst("registeredAddress",wu.registeredAddress),
         lst("destinationIndicator",wu.destinationIndicator),
         opts("preferreddeliverymethod",wu.preferredDeliveryMethod),
         lst("telexNumber",wu.telexNumber),
         lst("teletexTerminalIdentifier",wu.teletexTerminalIdentifier),
         lst("telephoneNumber",wu.telephoneNumber),
         lst("internationalISDNNumber",wu.internationalISDNNumber),
         lst("facsimileTelephoneNumber",wu.facsimileTelephoneNumber),
         lst("street",wu.street),
         lst("postOfficeBox",wu.postOfficeBox),
         lst("postalCode",wu.postalCode),
         lst("postalAddress",wu.postalAddress),
         lst("physicalDeliveryOfficeName",wu.physicalDeliveryOfficeName),
         lst("ou",wu.ou),
         lst("st",wu.st),
         lst("l",wu.l),

         // inetOrgPerson
         lst("audio",wu.audio),
         lst("businessCategory",wu.businessCategory),
         lst("carLicense",wu.carLicense),
         lst("teamNumber",wu.teamNumber),
         opts("displayName",wu.displayName),
         opts("employeeNumber",wu.employeeNumber),
         lst("employeeType",wu.employeeType),
         lst("givenName",wu.givenName),
         lst("homePhone",wu.homePhone),
         lst("homePostalAddress",wu.homePostalAddress),
         lst("initials",wu.initials),
         lst("jpegPhoto",wu.jpegPhoto),
         lst("labeledURI",wu.labeledURI),
         lst("mail",wu.mail),
         lst("manager",wu.manager),
         lst("mobile",wu.mobile),
         lst("o",wu.o),
         lst("pager",wu.pager),
         lst("photo",wu.photo),
         lst("roomNumber",wu.roomNumber),
         lst("secretary",wu.secretary),
         lst("uid",wu.uid),
         lst("userCertificate",wu.userCertificate),
         lst("x500uniqueIdentifier",wu.x500uniqueIdentifier),
         opts("preferredLanguage",wu.preferredLanguage),
         lst("userSMIMECertificate",wu.userSMIMECertificate),
         lst("userPKCS12",wu.userPKCS12),

         // webmailUser
         opts("webmailUserStatus",wu.webmailUserStatus),
         opti("webmailUserLevel",wu.webmailUserLevel),
         opts("webmailUserSgn",wu.webmailUserSgn),
         opts("webmailUserSalt",wu.webmailUserSalt),
         optb("webmailUserBlocked",wu.webmailUserBlocked),

        ])})}
    }
  }

}

