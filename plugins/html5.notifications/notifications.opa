package html5.notifications

// type Notifications.type =
//   {simple} / {html}

@client
HTML5_Notifications = {{

  support() =
    (%% notifications.support %%)()

  request(cb) =
    (%% notifications.request %%)(cb)

  enabled() =
    (%% notifications.enabled %%)()

  simple(title:string, description:string, icon_url_opt:option(string)) =
    (%% notifications.simple %%)(title, description, icon_url_opt)

}}
