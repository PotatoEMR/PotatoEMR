document.addEventListener('mousedown', function(e) {
    const elt = e.target.closest('[potato-drag]');
    if (!elt) return;
    
    let startX = e.clientX;
    let startY = e.clientY;
    let startRight = parseInt(window.getComputedStyle(elt).right, 10);
    let startTop = parseInt(window.getComputedStyle(elt).top, 10);
    let isDown = true;
    
    document.body.style.userSelect = 'none';
    
    function onMouseMove(e) {
        if (!isDown) return;
        
        const dx = e.clientX - startX;
        const dy = e.clientY - startY;
        
        elt.style.right = (startRight - dx) + 'px';
        elt.style.top = (startTop + dy) + 'px';
    }
    
    function onMouseUp() {
        isDown = false;
        document.body.style.userSelect = '';
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
    }
    
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
});