/**
 * @register {-> bool}
 */
function support() {
    return window.notification
	|| window.webkitNotifications
	|| navigator.mozNotification;
}

/**
 * @register {(bool -> void) -> bool}
 */
function request(cb) {
    if (window.webkitNotifications) {
	return window.webkitNotifications.checkPermission() == 0
	    || window.webkitNotifications.requestPermission(function(){
		cb(window.webkitNotifications.checkPermission() == 0)
	    });
    } else if (navigator.mozNotification) {
	return navigator.mozNotification.checkPermission() == 0
	    || navigator.mozNotification.requestPermission(function(){
		cb(navigator.mozNotification.checkPermission() == 0)
	    });
    }
}

/**
 * @register {-> bool}
 */
function enabled() {
    if (window.webkitNotifications) {
	return window.webkitNotifications.checkPermission() == 0;
    } else if (navigator.mozNotification) {
	return navigator.mozNotification.checkPermission() == 0;
    }
}

/**
 * @register {string, string, option(string) -> void}
 */
function simple(title, description, icon_url_opt) {
    function show(){
        var notif = window.webkitNotifications.createNotification(
            icon_url_opt, title, description);
        notif.addEventListener(
            'display',
            function() { setTimeout(function(){ notif.cancel() }, 5000) }
        );
        notif.addEventListener(
            'click',
            function() { this.cancel() }
        );
        notif.show();
    }
    if (window.webkitNotifications) {
        if(window.webkitNotifications.checkPermission() == 0){
            show();
        } else {
            window.webkitNotifications.requestPermission(function(){
                if(window.webkitNotifications.checkPermission() == 0) show()
            })
        }
    }
}
