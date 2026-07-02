// SECURITY: код детерминирован и вычислим из id — генерация должна переехать
// на сервер (случайный код в БД), иначе любой пользователь может перебрать
// коды классов простым перебором id.
// TODO(security): move class-code generation server-side (random code in DB).
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
