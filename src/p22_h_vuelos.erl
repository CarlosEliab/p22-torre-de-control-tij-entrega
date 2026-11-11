%% ===================================================================
%% @doc p22_h_vuelos — handler de `GET/POST /api/vuelos`.
%%
%% GET  : lista completa de vuelos (por id) con su estado y datos
%%        derivados del respaldo (uso general del tablero).
%% POST : crea un vuelo nuevo. El cuerpo JSON es opcional:
%%        {"destino":"CDMX","aerolinea":"Volaris",
%%         "entrada_seg":60,"hora_programada":1760000000}
%%        `entrada_seg' retrasa la entrada del vuelo N segundos (para
%%        que no se mueva tan rapido); `hora_programada' fija la hora
%%        Unix exacta (tiene prioridad).
%% ===================================================================
-module(p22_h_vuelos).

-export([init/2]).

init(Req0, State) ->
    Metodo = cowboy_req:method(Req0),
    #{codigo := Codigo, cuerpo := Cuerpo} = respuesta(Metodo, Req0),
    Resp = p22_http:json(Req0, Codigo, Cuerpo),
    {ok, Resp, State}.

respuesta(<<"GET">>, _Req) ->
    #{codigo => 200, cuerpo => #{ok => true, vuelos => lista_vuelos()}};
respuesta(<<"POST">>, Req) ->
    %% crea un vuelo AHORA (la demo puede dispararlo a mano). El cuerpo
    %% JSON es opcional: {"destino": "CDMX", "aerolinea": "Volaris"}.
    Opciones = opciones_de(p22_http:cuerpo_json(Req)),
    case p22_feed:nuevo_vuelo(Opciones) of
        {ok, Id} ->
            #{codigo => 201, cuerpo => #{ok => true, vuelo => Id}};
        {error, Razon} ->
            #{codigo => 503, cuerpo => #{ok => false, error => a_bin(Razon)}}
    end;
respuesta(_, _) ->
    #{codigo => 405, cuerpo => #{ok => false, error => <<"metodo no permitido">>}}.

%% Solo se aceptan campos conocidos y con el tipo correcto; cualquier
%% otra cosa se ignora (el vuelo se crea igual con valores simulados).
opciones_de({ok, Mapa}) ->
    Texto = listas([{destino, <<"destino">>},
                    {aerolinea, <<"aerolinea">>},
                    {aeronave, <<"aeronave">>},
                    {identificacion, <<"identificacion">>}], Mapa, #{}),
    Numeros = enteros([{entrada_seg, <<"entrada_seg">>},
                       {hora_programada, <<"hora_programada">>}], Mapa, Texto),
    Numeros;
opciones_de(error) ->
    #{}.

listas([], _Mapa, Acc) ->
    Acc;
listas([{Clave, Json} | Resto], Mapa, Acc) ->
    case maps:get(Json, Mapa, undefined) of
        V when is_binary(V), byte_size(V) > 0 ->
            listas(Resto, Mapa, Acc#{Clave => V});
        _ ->
            listas(Resto, Mapa, Acc)
    end.

enteros([], _Mapa, Acc) ->
    Acc;
enteros([{Clave, Json} | Resto], Mapa, Acc) ->
    case maps:get(Json, Mapa, undefined) of
        V when is_integer(V), V >= 0 ->
            enteros(Resto, Mapa, Acc#{Clave => V});
        V when is_float(V), V >= 0 ->
            enteros(Resto, Mapa, Acc#{Clave => round(V)});
        _ ->
            enteros(Resto, Mapa, Acc)
    end.

a_bin(B) when is_binary(B) -> B;
a_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
a_bin(I) when is_integer(I) -> integer_to_binary(I);
a_bin(T) -> unicode:characters_to_binary(io_lib:format("~p", [T])).

%% Snapshot de todos los vuelos del respaldo, ordenado por id, con el
%% ESTADO del vuelo vivo cuando exista (el respaldo es la imagen de
%% arranque; el statem es la verdad en caliente).
lista_vuelos() ->
    Vuelos =
        [vista_vuelo(Id, Info)
         || {Id, Info} <- p22_respaldo:todos_vuelos()],
    lists:sort(
      fun (A, B) -> maps:get(id, A) =< maps:get(id, B) end,
      Vuelos).

vista_vuelo(Id, Info) ->
    EstadoGuardado = maps:get(estado, Info, nada),
    Datos = maps:get(datos, Info, #{}),
    Vista =
        case p22_vuelo_statem:completo(Id) of
            {error, _} ->
                %% el proceso esta muerto o renaciendo: reportamos la
                %% imagen del respaldo (el tablero NO parpadea)
                #{id => Id, estado => EstadoGuardado, de_respaldo => true,
                  identificacion => maps:get(identificacion, Datos, <<>>),
                  aeronave => maps:get(aeronave, Datos, <<>>),
                  aerolinea => maps:get(aerolinea, Datos, <<>>),
                  destino => maps:get(destino, Datos, <<>>),
                  puerta => maps:get(puerta, Datos, undefined),
                  demora_min => maps:get(demora_min, Datos, 0),
                  hora_programada => maps:get(hora_programada, Datos, 0),
                  hora_estimada => maps:get(hora_estimada, Datos, undefined)};
            VistaViva ->
                VistaViva#{de_respaldo => false}
        end,
    Vista.
