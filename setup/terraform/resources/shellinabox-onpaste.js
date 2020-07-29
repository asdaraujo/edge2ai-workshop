document.onpaste = function(event){
    event.preventDefault();
    var items = (event.clipboardData || event.originalEvent.clipboardData).items;
    for (index in items) {
        var item = items[index];
        if ((item.kind === 'string') && (item.type.match('^text/plain'))){
            item.getAsString( function(str){
                str = str.replace(/\r/g, '');
                window.shellinabox.keysPressed(str);
            });
        }
    }
}
