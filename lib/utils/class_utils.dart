String classCode(int id) {
  const c = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var s = '';
  var n = id * 1337 + 42;
  for (var i = 0; i < 6; i++) {
    s += c[n % c.length];
    n = n ~/ c.length + id * 7;
  }
  return s.substring(0, 6);
}
