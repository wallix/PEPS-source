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
 * Types and functions to handle the webmailContact schema data.
 *
 * @destination public
 * @stabilization work in progress
 **/

type Ldap.webmailContact = {

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

  // webmailContact
  option(string) webmailContactId,
  option(string) webmailContactVisibility,
  option(bool) webmailContactBlocked,
}

module WebmailContact {

  Ldap.webmailContact default_webmailContact = {

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

    // webmailContact
    webmailContactId: {none},
    webmailContactVisibility: {none},
    webmailContactBlocked: {none},
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

  private function opts(__name, RPC.Json.json json, Ldap.webmailContact rcrd, option(string) cur,
                        (Ldap.webmailContact, option(string) -> Ldap.webmailContact) set) { // ie. SINGLE-VALUE
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
    default: {bad:@intl("Bad JSON for string object {json}")};
    }
  }

  private function opti(__name, RPC.Json.json json, Ldap.webmailContact rcrd, option(int) cur,
                        (Ldap.webmailContact, option(int) -> Ldap.webmailContact) set) { // ie. SINGLE-VALUE
    //Ansi.jlog("opti: name=%y{__name}%d cur=%m{cur}%d json=%g{json}%d");
    function chks(string Int_) {
      match (Int.of_string_opt(Int_)) {
      case {some:Int}:
        match (cur) {
        case {none}: {ok:set(rcrd, {some:Int})};
        case {some:_}: {multiple};
        }
      case {none}: {bad:@intl("Bad integer string {Int}")};
      }
    }
    function chk(int Int) { match (cur) { case {none}: {ok:set(rcrd, {some:Int})}; case {some:_}: {multiple}; } }
    match (json) {
    case {~String}: chks(String);
    case {~Int}: chk(Int);
    case {List:[]}: {ok:rcrd};
    case {List:[{~String}]}: chks(String);
    case {List:[{~Int}]}: chk(Int);
    default: {bad:@intl("Bad JSON for int object {json}")};
    }
  }

  private function optb(__name, RPC.Json.json json, Ldap.webmailContact rcrd, option(bool) cur,
                        (Ldap.webmailContact, option(bool) -> Ldap.webmailContact) set) { // ie. SINGLE-VALUE
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
      default: {bad:@intl("Bad boolean string {Bool}")};
      }
    }
    function chk(bool Bool) { match (cur) { case {none}: {ok:set(rcrd, {some:Bool})}; case {some:_}: {multiple}; } }
    match (json) {
    case {~String}: chks(String);
    case {~Bool}: chk(Bool);
    case {List:[]}: {ok:rcrd};
    case {List:[{~String}]}: chks(String);
    case {List:[{~Bool}]}: chk(Bool);
    default: {bad:@intl("Bad JSON for boolean object {json}")};
    }
  }

  private function chkMultiple(aux, flds, res) {
    match (res) {
    case {ok:rcrd}: aux(flds, rcrd);
    case {multiple}: {failure:@intl("Multiple SINGLE-VALUE entries")};
    case {~bad}: {failure:bad};
    }
  }

  function parseJson(RPC.Json.json json) {
    match (json) {
    case {~Record}:
      recursive function aux(flds, wc) {
        match (flds) {
        case []: {success:wc};
        case [fld|flds]:
          //Ansi.jlog("fld: %b{fld}%d")
          match (String.lowercase(fld.f1)) {

          // top
          case "dn":
            chkMultiple(aux, flds, opts("dn", fld.f2, wc, wc.dn,
                        function (wc, dn) { {wc with ~dn} }));
          case "controls": aux(flds, wc);  // ignore this, it's rarely used

          // person
          case "sn": aux(flds,lst("sn", fld.f2, wc, wc.sn, function (wc, sn) { {wc with ~sn} }));
          case "surname": aux(flds,lst("surname", fld.f2, wc, wc.sn, function (wc, sn) { {wc with ~sn} }));
          case "cn": aux(flds,lst("cn", fld.f2, wc, wc.cn, function (wc, cn) { {wc with ~cn} }));
          case "commonname": aux(flds,lst("commonName", fld.f2, wc, wc.cn, function (wc, cn) { {wc with ~cn} }));
          case "userpassword":
            chkMultiple(aux, flds, opts("userPassword", fld.f2, wc, wc.userPassword,
                        function (wc, userPassword) { {wc with ~userPassword} }));
          case "seealso":
            chkMultiple(aux, flds, opts("seeAlso", fld.f2, wc, wc.seeAlso,
                        function (wc, seeAlso) { {wc with ~seeAlso} }));
          case "description":
            chkMultiple(aux, flds, opts("description", fld.f2, wc, wc.description,
                        function (wc, description) { {wc with ~description} }));

          //organizationalPerson
          case "title":
            aux(flds,lst("title", fld.f2, wc, wc.title,
                function (wc, title) { {wc with ~title} }));
          case "x121address":
            aux(flds,lst("x121Address", fld.f2, wc, wc.x121Address,
                function (wc, x121Address) { {wc with ~x121Address} }));
          case "registeredaddress":
            aux(flds,lst("registeredAddress", fld.f2, wc, wc.registeredAddress,
                function (wc, registeredAddress) { {wc with ~registeredAddress} }));
          case "destinationindicator":
            aux(flds,lst("destinationIndicator", fld.f2, wc, wc.destinationIndicator,
                function (wc, destinationIndicator) { {wc with ~destinationIndicator} }));
          case "preferreddeliverymethod":
            chkMultiple(aux, flds, opts("preferredDeliveryMethod", fld.f2, wc, wc.preferredDeliveryMethod,
              function (wc, preferredDeliveryMethod) { {wc with ~preferredDeliveryMethod} }));
          case "telexnumber":
            aux(flds,lst("telexNumber", fld.f2, wc, wc.telexNumber,
                function (wc, telexNumber) { {wc with ~telexNumber} }));
          case "teletexterminalidentifier":
            aux(flds,lst("teletexTerminalIdentifier", fld.f2, wc, wc.teletexTerminalIdentifier,
                function (wc, teletexTerminalIdentifier) { {wc with ~teletexTerminalIdentifier} }));
          case "telephonenumber":
            aux(flds,lst("telephoneNumber", fld.f2, wc, wc.telephoneNumber,
                function (wc, telephoneNumber) { {wc with ~telephoneNumber} }));
          case "internationalisdnnumber":
            aux(flds,lst("internationalISDNNumber", fld.f2, wc, wc.internationalISDNNumber,
                function (wc, internationalISDNNumber) { {wc with ~internationalISDNNumber} }));
          case "facsimiletelephonenumber":
            aux(flds,lst("facsimileTelephoneNumber", fld.f2, wc, wc.facsimileTelephoneNumber,
                function (wc, facsimileTelephoneNumber) { {wc with ~facsimileTelephoneNumber} }));
          case "street":
            aux(flds,lst("street", fld.f2, wc, wc.street,
                function (wc, street) { {wc with ~street} }));
          case "postofficebox":
            aux(flds,lst("postOfficeBox", fld.f2, wc, wc.postOfficeBox,
                function (wc, postOfficeBox) { {wc with ~postOfficeBox} }));
          case "postalcode":
            aux(flds,lst("postalCode", fld.f2, wc, wc.postalCode,
                function (wc, postalCode) { {wc with ~postalCode} }));
          case "postaladdress":
            aux(flds,lst("postalAddress", fld.f2, wc, wc.postalAddress,
                function (wc, postalAddress) { {wc with ~postalAddress} }));
          case "physicaldeliveryofficename":
            aux(flds,lst("physicalDeliveryOfficeName", fld.f2, wc, wc.physicalDeliveryOfficeName,
                function (wc, physicalDeliveryOfficeName) { {wc with ~physicalDeliveryOfficeName} }));
          case "ou":
            aux(flds,lst("ou", fld.f2, wc, wc.ou,
                function (wc, ou) { {wc with ~ou} }));
          case "st":
            aux(flds,lst("st", fld.f2, wc, wc.st,
                function (wc, st) { {wc with ~st} }));
          case "l":
            aux(flds,lst("l", fld.f2, wc, wc.l,
                function (wc, l) { {wc with ~l} }));

          // inetOrgPerson
          case "audio":
            aux(flds,lst("audio", fld.f2, wc, wc.audio,
                function (wc, audio) { {wc with ~audio} }));
          case "businesscategory":
            aux(flds,lst("businessCategory", fld.f2, wc, wc.businessCategory,
                function (wc, businessCategory) { {wc with ~businessCategory} }));
          case "carlicense":
            aux(flds,lst("carLicense", fld.f2, wc, wc.carLicense,
                function (wc, carLicense) { {wc with ~carLicense} }));
          case "teamnumber":
            aux(flds,lst("teamNumber", fld.f2, wc, wc.teamNumber,
                function (wc, teamNumber) { {wc with ~teamNumber} }));
          case "displayname":
            chkMultiple(aux, flds, opts("displayName", fld.f2, wc, wc.displayName,
                        function (wc, displayName) { {wc with ~displayName} }));
          case "employeenumber":
            chkMultiple(aux, flds, opts("employeeNumber", fld.f2, wc, wc.employeeNumber,
                        function (wc, employeeNumber) { {wc with ~employeeNumber} }));
          case "employeetype":
            aux(flds,lst("employeeType", fld.f2, wc, wc.employeeType,
                function (wc, employeeType) { {wc with ~employeeType} }));
          case "givenname":
            aux(flds,lst("givenName", fld.f2, wc, wc.givenName,
                function (wc, givenName) { {wc with ~givenName} }));
          case "homephone":
            aux(flds,lst("homePhone", fld.f2, wc, wc.homePhone,
                function (wc, homePhone) { {wc with ~homePhone} }));
          case "homepostaladdress":
            aux(flds,lst("homePostalAddress", fld.f2, wc, wc.homePostalAddress,
                function (wc, homePostalAddress) { {wc with ~homePostalAddress} }));
          case "initials":
            aux(flds,lst("initials", fld.f2, wc, wc.initials,
                function (wc, initials) { {wc with ~initials} }));
          case "jpegphoto":
            aux(flds,lst("jpegPhoto", fld.f2, wc, wc.jpegPhoto,
                function (wc, jpegPhoto) { {wc with ~jpegPhoto} }));
          case "labeleduri":
            aux(flds,lst("labeledURI", fld.f2, wc, wc.labeledURI,
                function (wc, labeledURI) { {wc with ~labeledURI} }));
          case "mail":
            aux(flds,lst("mail", fld.f2, wc, wc.mail,
                function (wc, mail) { {wc with ~mail} }));
          case "manager":
            aux(flds,lst("manager", fld.f2, wc, wc.manager,
                function (wc, manager) { {wc with ~manager} }));
          case "mobile":
            aux(flds,lst("mobile", fld.f2, wc, wc.mobile,
                function (wc, mobile) { {wc with ~mobile} }));
          case "o":
            aux(flds,lst("o", fld.f2, wc, wc.o,
                function (wc, o) { {wc with ~o} }));
          case "pager":
            aux(flds,lst("pager", fld.f2, wc, wc.pager,
                function (wc, pager) { {wc with ~pager} }));
          case "photo":
            aux(flds,lst("photo", fld.f2, wc, wc.photo,
                function (wc, photo) { {wc with ~photo} }));
          case "roomnumber":
            aux(flds,lst("roomNumber", fld.f2, wc, wc.roomNumber,
                function (wc, roomNumber) { {wc with ~roomNumber} }));
          case "secretary":
            aux(flds,lst("secretary", fld.f2, wc, wc.secretary,
                function (wc, secretary) { {wc with ~secretary} }));
          case "uid":
            aux(flds,lst("uid", fld.f2, wc, wc.uid,
                function (wc, uid) { {wc with ~uid} }));
          case "usercertificate":
            aux(flds,lst("userCertificate", fld.f2, wc, wc.userCertificate,
                function (wc, userCertificate) { {wc with ~userCertificate} }));
          case "x500uniqueidentifier":
            aux(flds,lst("x500uniqueIdentifier", fld.f2, wc, wc.x500uniqueIdentifier,
                function (wc, x500uniqueIdentifier) { {wc with ~x500uniqueIdentifier} }));
          case "preferredlanguage":
            chkMultiple(aux, flds, opts("preferredLanguage", fld.f2, wc, wc.preferredLanguage,
                        function (wc, preferredLanguage) { {wc with ~preferredLanguage} }));
          case "usersmimecertificate":
            aux(flds,lst("userSMIMECertificate", fld.f2, wc, wc.userSMIMECertificate,
                function (wc, userSMIMECertificate) { {wc with ~userSMIMECertificate} }));
          case "userpkcs12":
            aux(flds,lst("userPKCS12", fld.f2, wc, wc.userPKCS12,
                function (wc, userPKCS12) { {wc with ~userPKCS12} }));

          // webmailContact
          case "webmailcontactid":
            chkMultiple(aux, flds, opts("webmailContactId", fld.f2, wc, wc.webmailContactVisibility,
                        function (wc, webmailContactVisibility) { {wc with ~webmailContactVisibility} }));
          case "webmailcontactvisibility":
            chkMultiple(aux, flds, opts("webmailContactVisibility", fld.f2, wc, wc.webmailContactVisibility,
                        function (wc, webmailContactVisibility) { {wc with ~webmailContactVisibility} }));
          case "webmailcontactblocked":
            chkMultiple(aux, flds, optb("webmailContactBlocked", fld.f2, wc, wc.webmailContactBlocked,
                        function (wc, webmailContactBlocked) { {wc with ~webmailContactBlocked} }));

          default:
            {failure:@intl("Bad webmailContact field '{fld.f1}'")};
          }
        }
      }
      aux(Record, default_webmailContact);
    default: {failure:@intl("JSON value is not Record")};
    }
  }

  function outcome(string,string) toJsonString(Ldap.webmailContact wc) {
    missing = List.flatten([if (List.is_empty(wc.cn)) ["cn"] else [],
                            if (List.is_empty(wc.sn)) ["sn"] else []])
    if (not(List.is_empty(missing)))
      {failure:"Missing MUST fields {String.concat(",",missing)}"}
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
         ("objectclass",{List:[{String:"webmailContact"}]})],
         opts("dn",wc.dn),

         // person
         lst("sn",wc.sn),
         lst("cn",wc.cn),
         opts("userPassword",wc.userPassword),
         opts("seeAlso",wc.seeAlso),
         opts("description",wc.description),

         //organizationalPerson
         lst("title",wc.title),
         lst("x121Address",wc.x121Address),
         lst("registeredAddress",wc.registeredAddress),
         lst("destinationIndicator",wc.destinationIndicator),
         opts("preferreddeliverymethod",wc.preferredDeliveryMethod),
         lst("telexNumber",wc.telexNumber),
         lst("teletexTerminalIdentifier",wc.teletexTerminalIdentifier),
         lst("telephoneNumber",wc.telephoneNumber),
         lst("internationalISDNNumber",wc.internationalISDNNumber),
         lst("facsimileTelephoneNumber",wc.facsimileTelephoneNumber),
         lst("street",wc.street),
         lst("postOfficeBox",wc.postOfficeBox),
         lst("postalCode",wc.postalCode),
         lst("postalAddress",wc.postalAddress),
         lst("physicalDeliveryOfficeName",wc.physicalDeliveryOfficeName),
         lst("ou",wc.ou),
         lst("st",wc.st),
         lst("l",wc.l),

         // inetOrgPerson
         lst("audio",wc.audio),
         lst("businessCategory",wc.businessCategory),
         lst("carLicense",wc.carLicense),
         lst("teamNumber",wc.teamNumber),
         opts("displayName",wc.displayName),
         opts("employeeNumber",wc.employeeNumber),
         lst("employeeType",wc.employeeType),
         lst("givenName",wc.givenName),
         lst("homePhone",wc.homePhone),
         lst("homePostalAddress",wc.homePostalAddress),
         lst("initials",wc.initials),
         lst("jpegPhoto",wc.jpegPhoto),
         lst("labeledURI",wc.labeledURI),
         lst("mail",wc.mail),
         lst("manager",wc.manager),
         lst("mobile",wc.mobile),
         lst("o",wc.o),
         lst("pager",wc.pager),
         lst("photo",wc.photo),
         lst("roomNumber",wc.roomNumber),
         lst("secretary",wc.secretary),
         lst("uid",wc.uid),
         lst("userCertificate",wc.userCertificate),
         lst("x500uniqueIdentifier",wc.x500uniqueIdentifier),
         opts("preferredLanguage",wc.preferredLanguage),
         lst("userSMIMECertificate",wc.userSMIMECertificate),
         lst("userPKCS12",wc.userPKCS12),

         // webmailContact
         opts("webmailContactId", wc.webmailContactId),
         opts("webmailContactVisibility", wc.webmailContactVisibility),
         optb("webmailContactBlocked", wc.webmailContactBlocked),

        ])})}
    }
  }

}

