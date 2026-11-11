%% ===================================================================
%% @doc p22_h_simulacion — API de control del ritmo de simulacion.
%%
%%   GET  /api/simulacion          estado actual (perfil, pausa, tiempos)
%%   POST /api/simulacion/ritmo    cambia perfil y/o tiempos en caliente
%%   POST /api/simulacion/pausar   congela el feed
%%   POST /api/simulacion/reanudar reanuda el feed
%%
%% Cuerpo de /ritmo (todas las claves son opcionales):
%%   {"perfil":"muy_lento|lento|normal|rapido|personalizado",
%%    "feed_ms":15000,
%%    "nuevo_vuelo_cada_ms":90000,
%%    "espera_entrada_ms":60000,
%%    "abordaje_ms":60000,
%%    "vuelo_ms":120000}
%%
%% Tambien acepta la forma amigable "nuevo_vuelo_cada_seg" (segundos).
%% La validacion real vive en p22_feed; aqui solo se traduce HTTP <-> dominio.
%% ===================================================================
-module(p22_h_simulacion).

-export([init/2]).

-define(CAMPOS_MS, [feed_ms, nuevo_vuelo_cada_ms, espera_entrada_ms,
                    abordaje_ms, vuelo_ms]).

init(Req0, State) ->
    Metodo = cowboy_req:method(Req0),
    Accion = cowboy_req:binding(accion, Req0, undefined),
    {Codigo, Cuerpo} = atender(Metodo, Accion, Req0),
    {ok, p22_http:json(Req0, Codigo, Cuerpo), State}.

atender(<<"GET">>, undefined, _Req) ->
    estado();
atender(<<"POST">>, <<"ritmo">>, Req) ->
    aplicar_ritmo(p22_http:cuerpo_json(Req));
atender(<<"POST">>, <<"pausar">>, _Req) ->
    try p22_feed:pausar() of
        ok -> {200, #{ok => true, accion => <<"pausar">>,
                      simulacion => p22_feed:estado_simulacion()}}
    catch
        _:_ -> servicio_no_disponible()
    end;
atender(<<"POST">>, <<"reanudar">>, _Req) ->
    try p22_feed:reanudar() of
        ok -> {200, #{ok => true, accion => <<"reanudar">>,
                      simulacion => p22_feed:estado_simulacion()}}
    catch
        _:_ -> servicio_no_disponible()
    end;
atender(<<"GET">>, _Otra, _Req) ->
    {404, #{ok => false, error => <<"ruta de simulacion desconocida">>}};
atender(_, _, _Req) ->
    {405, #{ok => false, error => <<"metodo no permitido">>}}.

estado() ->
    try p22_feed:estado_simulacion() of
        Simulacion -> {200, #{ok => true, simulacion => Simulacion}}
    catch
        _:_ -> servicio_no_disponible()
    end.

aplicar_ritmo({ok, Mapa}) ->
    Cambios = normalizar(Mapa),
    case Cambios of
        {error, Razon} ->
            {400, #{ok => false, error => Razon}};
        _ ->
            try p22_feed:ajustar_ritmo(Cambios) of
                {ok, Simulacion} ->
                    {200, #{ok => true, simulacion => Simulacion}};
                {error, Razon} ->
                    {409, #{ok => false, error => a_bin(Razon)}}
            catch
                _:_ -> servicio_no_disponible()
            end
    end;
aplicar_ritmo(error) ->
    {400, #{ok => false, error => <<"cuerpo JSON invalido">>}}.

%% Convierte claves binarias del JSON a atomos conocidos y normaliza
%% segundos -> milisegundos cuando hace falta. Las claves desconocidas
%% se ignoran en lugar de crear atomos arbitrarios.
normalizar(Mapa) ->
    maps:fold(fun normalizar_par/3, #{}, Mapa).

normalizar_par(Clave0, Valor, Acc) ->
    case clave(Clave0) of
        desconocida ->
            Acc;
        perfil ->
            Acc#{perfil => valor_perfil(Valor)};
        {seg, Campo} ->
            Acc#{Campo => a_ms(Valor)};
        Campo ->
            Acc#{Campo => a_entero(Valor)}
    end.

clave(perfil) -> perfil;
clave(<<"perfil">>) -> perfil;
clave(feed_ms) -> feed_ms;
clave(<<"feed_ms">>) -> feed_ms;
clave(nuevo_vuelo_cada_ms) -> nuevo_vuelo_cada_ms;
clave(<<"nuevo_vuelo_cada_ms">>) -> nuevo_vuelo_cada_ms;
clave(espera_entrada_ms) -> espera_entrada_ms;
clave(<<"espera_entrada_ms">>) -> espera_entrada_ms;
clave(abordaje_ms) -> abordaje_ms;
clave(<<"abordaje_ms">>) -> abordaje_ms;
clave(vuelo_ms) -> vuelo_ms;
clave(<<"vuelo_ms">>) -> vuelo_ms;
clave(nuevo_vuelo_cada_seg) -> {seg, nuevo_vuelo_cada_ms};
clave(<<"nuevo_vuelo_cada_seg">>) -> {seg, nuevo_vuelo_cada_ms};
clave(_) -> desconocida.

valor_perfil(P) when is_binary(P) ->
    try binary_to_existing_atom(P, utf8)
    catch _:_ -> P
    end;
valor_perfil(P) -> P.

a_ms(V) when is_number(V) -> round(V * 1000);
a_ms(V) -> V.

a_entero(V) when is_float(V) -> round(V);
a_entero(V) -> V.

a_bin(B) when is_binary(B) -> B;
a_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
a_bin(I) when is_integer(I) -> integer_to_binary(I);
a_bin(T) -> unicode:characters_to_binary(io_lib:format("~p", [T])).

servicio_no_disponible() ->
    {503, #{ok => false, error => <<"servicio de simulacion no disponible">>}}.
