python -c "
path = r'chrome\android\java\src\org\chromium\chrome\browser\compositor\layouts\ToolbarSwipeLayout.java'
with open(path, 'rb') as f:
    data = f.read()
if data.startswith(b'\xef\xbb\xbf'):
    data = data[3:]
with open(path, 'wb') as f:
    f.write(data)
"