package mailparser

type MailParser.header = {string key, list(string) value}
type MailParser.headers = list(MailParser.header)

type MailParser.address = {string address, option(string) name}
type MailParser.addresses = list(MailParser.address)

type MailParser.attachment = {
	string contentType,
	string fileName,
  string contentDisposition,
  string contentId,
  string transferEncoding,
  int length,
  string checksum,
  binary content  // Buffer in node.
}
type MailParser.attachments = list(MailParser.attachment)

type MailParser.mail = {
	MailParser.headers headers, // Unprocessed headers in the form of - {key: value} - if there were multiple fields with the same key then the value is an array.
	MailParser.addresses from, 	// An array of parsed From addresses - [{address:'sender@example.com',name:'Sender Name'}] (should be only one though).
	MailParser.addresses to, 		// An array of parsed To addresses.
	MailParser.addresses cc, 		// An array of parsed Cc addresses.
	MailParser.addresses bcc,   // An array of parsed 'Bcc' addresses.
	string subject,    					// The subject line.
	// list(string) references, 		// An array of reference message id values (not set if no reference values present).
	// list(string) inReplyTo, 		// An array of In-Reply-To message id values (not set if no in-reply-to values present).
	// string priority,  					// Priority of the e-mail, always one of the following: normal (default), high, low.
	string text,								// Text body.
	string html, 								// Html body.
	// string date, 								// Date field.
	MailParser.attachments attachments  // An array of attachments.
}

module MailParser {

	/** Asynchrnous parsing function. */
	@async function void parse(string raw, (option(MailParser.mail) -> void) callback) {
		%%MailParser.parse%%(raw, callback)
	}

	/** Synchronous version. */
	function option(MailParser.mail) parsesync(string raw) {
    function k(cont) {
      callback = Continuation.return(cont, _)
      parse(raw, callback)
    }
    @callcc(k)
	}

	/** Extract an header from the parsed message. */
	function get_header(MailParser.mail mail, key) {
		List.find(function (header) { String.lowercase(header.key) == String.lowercase(key) }, mail.headers)
	}

}