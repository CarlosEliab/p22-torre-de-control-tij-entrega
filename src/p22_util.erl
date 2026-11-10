%% ===================================================================
%% @doc p22_util — helpers del proyecto 22 (torre de control TIJ).
%%
%% Contiene utilidades compartidas: conversion a JSON para la API y el
%% WebSocket, formateo de tiempos y constantes del dominio.
%%
%% Nota: usamos el modulo `json` nativo de OTP 27 para serializar. El
%% encoder de `json` solo acepta claves y cadenas en binario, por eso
%% `map_a_json/1` normaliza atomos a binarios de forma recursiva.
%% ===================================================================
-module(p22_util).

-export([map_a_json/1, json_a_texto/1, fecha/1, hhmm/1, camelize_estados/0]).

%% Estados del ciclo de vida de un vuelo (en el orden del tablero).
camelize_estados() ->
    ['programado', 'demorado', 'abordando', 'despego', 'aterrizado', 'cancelado'].

%% @doc Serializa un mapa/lista de Erlang a binario JSON.
%% Los atomos pasan a binario y todas las claves terminan en binario.
json_a_texto(Termino) ->
    json:encode(map_a_json(Termino)).

%% @doc Conversion recursiva: atomos -> binario, listas ordinarias ok.
%% Los identificadores de vuelo y puertas son atomos internos, pero la
%% capa web siempre habla binario para que `json` pueda serializar.
map_a_json(A) when A =:= true orelse A =:= false ->
    A;
map_a_json(undefined) ->
    null;
map_a_json(nil) ->
    null;
map_a_json(null) ->
    null;
map_a_json(A) when is_atom(A) ->
    atom_to_binary(A, utf8);
map_a_json(I) when is_integer(I) ->
    I;
map_a_json(F) when is_float(F) ->
    F;
map_a_json(B) when is_binary(B) ->
    B;
%% Las "cadenas" en Erlang son listas de enteros; una lista de
%% binarios, atomos o mapas NO lo es y debe viajar como arreglo JSON.
%% (Antes, `motivos => [<<"niebla">>]' se convertia en el texto
%% "niebla" en vez de en ["niebla"], y el tablero no podia recorrerlo.)
map_a_json([]) ->
    [];
map_a_json(L) when is_list(L) ->
    case es_cadena(L) of
        true -> unicode:characters_to_binary(L);
        false -> [map_a_json(X) || X <- L]
    end;
map_a_json(M) when is_map(M) ->
    #{map_a_json(K) => map_a_json(V) || K := V <- M}.

%% @doc true solo si TODOS los elementos son enteros (puntos de codigo).
es_cadena([C | Resto]) when is_integer(C), C >= 0 ->
    es_cadena(Resto);
es_cadena([]) ->
    true;
es_cadena(_) ->
    false.

%% @doc Fecha legible (UTC) a partir de segundos de epoca.
fecha(Segs) when is_integer(Segs) ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(Segs, second),
    io_lib:format("~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0wZ", [Y, Mo, D, H, Mi, S]).

%% @doc Solo hora:minuto, para badges del tablero.
hhmm(Segs) when is_integer(Segs) ->
    {{_, _, _}, {H, Mi, _}} = calendar:system_time_to_universal_time(Segs, second),
    io_lib:format("~2..0w:~2..0w", [H, Mi]).
