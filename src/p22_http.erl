%% ===================================================================
%% @doc p22_http — helpers compartidos para los handlers cowboy:
%% responder con JSON y leer cuerpos JSON.
%% ===================================================================
-module(p22_http).

-export([json/2, json/3, cuerpo_json/1]).

%% @doc Responde 200 con `Mapa' serializado a JSON.
json(Req0, Mapa) ->
    json(Req0, 200, Mapa).

%% @doc Responde con codigo arbitrario y `Mapa' a JSON.
json(Req0, Codigo, Mapa) ->
    Resp =
        cowboy_req:reply(Codigo,
                         #{<<"content-type">> => <<"application/json; charset=utf-8">>},
                         p22_util:json_a_texto(Mapa),
                         Req0),
    Resp.

%% @doc Cuerpo JSON -> {ok, mapa_de_binarios}. `error' si no es JSON valido.
cuerpo_json(Req0) ->
    Resultado = cowboy_req:read_body(Req0),
    case Resultado of
        {ok, Bin, _Req} when is_binary(Bin), Bin =/= <<>> ->
            try
                case json:decode(Bin) of
                    M when is_map(M) -> {ok, M};
                    _ -> error
                end
            catch
                _:_ -> error
            end;
        {ok, <<>>, _Req} ->
            error;
        _ ->
            error
    end.
