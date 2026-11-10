%% ===================================================================
%% @doc p22_h_index — `GET /`: el tablero de la torre (pagina unica).
%%
%% Sirve `priv/index.html`, que hace TODO el trabajo del usuario:
%% kanban de estados, detalle de vuelo, historial, reconexion del
%% WebSocket, colores por estado, en espanol, legible en celular.
%%
%% Busqueda del archivo: en un release `code:priv_dir/1` apunta a
%% lib/App-vsn/priv. En desarrollo con rebar3 en Windows el enlace
%% `_build/.../App/priv` puede quedar roto (rebar no logra crear el
%% symlink y deja un archivo vacio), asi que se prueban tambien la
%% ruta de la fuente (cuatro niveles arriba de la app) y `priv/` del
%% directorio de trabajo. La primera ruta legible gana.
%% ===================================================================
-module(p22_h_index).

-export([init/2]).

init(Req0, State) ->
    case leer_tablero() of
        {ok, Contenido} ->
            Req = cowboy_req:reply(200,
                                   #{<<"content-type">> =>
                                         <<"text/html; charset=utf-8">>},
                                   Contenido,
                                   Req0),
            {ok, Req, State};
        {error, Rutas} ->
            logger:error("no se encontro priv/index.html; probe: ~p", [Rutas]),
            Req = cowboy_req:reply(500,
                                   #{<<"content-type">> =>
                                         <<"text/plain; charset=utf-8">>},
                                   <<"Tablero no disponible: falta priv/index.html">>,
                                   Req0),
            {ok, Req, State}
    end.

leer_tablero() ->
    Rutas = rutas_candidatas(),
    case [R || R <- Rutas, filelib:is_regular(R)] of
        [Ruta | _] ->
            file:read_file(Ruta);
        [] ->
            {error, Rutas}
    end.

rutas_candidatas() ->
    Ebin = filename:dirname(code:which(?MODULE)),
    AppDir = filename:dirname(Ebin),
    lists:usort(
      rutas_priv() ++
      [filename:join([AppDir, "priv", "index.html"]),
       %% _build/<perfil>/lib/<app> -> raiz del proyecto -> priv
       filename:join([AppDir, "..", "..", "..", "..", "priv", "index.html"]),
       filename:join(["priv", "index.html"])]).

rutas_priv() ->
    case code:priv_dir(p22_torre_de_control_tij) of
        Dir when is_list(Dir) ->
            [filename:join(Dir, "index.html")];
        _ ->
            []
    end.
