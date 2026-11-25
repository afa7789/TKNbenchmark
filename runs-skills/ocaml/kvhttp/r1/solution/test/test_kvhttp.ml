open Kvhttp

let req ?(body = "") meth path : Http.request = { meth; path; headers = []; body }
let status store meth path ?body () = (Router.handle store (req ?body meth path)).status

let () =
  let s = Store.create () in
  assert (status s "GET" "/health" () = 200);
  assert (status s "POST" "/health" () = 405);
  assert (status s "GET" "/nope" () = 404);
  assert (status s "GET" "/kv/" () = 400);
  assert (status s "GET" "/kv/a/b" () = 400);
  assert (status s "GET" "/kv/bad.key" () = 400);
  assert (status s "GET" ("/kv/" ^ String.make 65 'a') () = 400);
  assert (status s "PUT" ("/kv/" ^ String.make 64 'a') ~body:"x" () = 201);
  assert (status s "PUT" "/kv/b" ~body:"1" () = 201);
  assert (status s "PUT" "/kv/b" ~body:"2" () = 200);
  assert (String.equal (Router.handle s (req "GET" "/kv/b")).body "2");
  assert (status s "PATCH" "/kv/b" () = 405);
  assert (status s "POST" "/kv" () = 405);
  assert (String.equal (Router.handle s (req "GET" "/kv")).body
            (Printf.sprintf "[%S,\"b\"]" (String.make 64 'a')));
  assert (status s "DELETE" "/kv/b" () = 204);
  assert (status s "DELETE" "/kv/b" () = 404);
  assert (status s "GET" "/kv/b" () = 404);
  (match Http.parse_head "GET /x HTTP/1.1\r\nHost: a\r\nContent-Length: 3" with
   | Ok ("GET", "/x", [ ("host", "a"); ("content-length", "3") ]) -> ()
   | Ok _ | Error _ -> assert false);
  assert (Result.is_error (Http.parse_head "GARBAGE"));
  print_endline "ok"
