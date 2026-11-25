open Kvhttp

let check name cond = if not cond then failwith ("test failed: " ^ name)

let status store meth path ?(body = "") () =
  (Router.handle store ~meth ~path ~body).Response.status

let () =
  let s = Store.create () in
  check "health" (status s "GET" "/health" () = 200);
  check "health 405" (status s "POST" "/health" () = 405);
  check "put new" (status s "PUT" "/kv/a" ~body:"x" () = 201);
  check "put replace" (status s "PUT" "/kv/a" ~body:"y" () = 200);
  check "get" ((Router.handle s ~meth:"GET" ~path:"/kv/a" ~body:"").body = "y");
  check "empty key" (status s "GET" "/kv/" () = 400);
  check "slash key" (status s "GET" "/kv/a/b" () = 400);
  check "long key" (status s "GET" ("/kv/" ^ String.make 65 'a') () = 400);
  check "max key" (status s "GET" ("/kv/" ^ String.make 64 'a') () = 404);
  check "patch" (status s "PATCH" "/kv/a" () = 405);
  check "list 405" (status s "DELETE" "/kv" () = 405);
  check "unknown" (status s "GET" "/kvx" () = 404);
  ignore (Store.put s "B" "");
  check "list"
    ((Router.handle s ~meth:"GET" ~path:"/kv" ~body:"").body = {|["B","a"]|});
  check "delete" (status s "DELETE" "/kv/a" () = 204);
  check "delete again" (status s "DELETE" "/kv/a" () = 404)
