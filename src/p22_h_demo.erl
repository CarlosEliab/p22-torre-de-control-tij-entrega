%% ===================================================================
%% @doc p22_h_demo — `POST /api/demo/:accion`.
%%
%% Expone los controles del escenario para la presentacion:
%%   niebla         -> demora 20 min todas las salidas programadas
%%   caos           -> mata un proceso de vuelo (reconstruccion)
%%   fuera_de_orden -> envia una secuencia vieja (debe ignorarse)
%%   pausar / reanudar -> detiene o reanuda el feed simulado
%%
%% Son mutaciones: solo POST. La logica vive en p22_feed; aqui solo se
%% traduce HTTP <-> dominio y se protege contra el feed en reinicio.
%% ===================================================================
-module(p22_h_demo).

-export([init/2]).

init(Req0, State) ->
    Metodo = cowboy_req:method(Req0),
    Accion = cowboy_req:binding(accion, Req0),
    {Codigo, Cuerpo} =
        case Metodo of
            <<"POST">> ->
                try ejecutar(Accion)
                catch
                    _:_ ->
                        {503, #{ok => false,
                                error => <<"servicio no disponible, reintenta">>}}
                end;
            _ ->
                {405, #{ok => false, error => <<"metodo no permitido">>}}
        end,
    {ok, p22_http:json(Req0, Codigo, Cuerpo), State}.

ejecutar(<<"niebla">>) ->
    {ok, N} = p22_feed:niebla(),
    {200, #{ok => true, accion => <<"niebla">>, vuelos_demorados => N}};
ejecutar(<<"caos">>) ->
    case p22_feed:inyectar_caos() of
        {ok, Id} ->
            {200, #{ok => true, accion => <<"caos">>, vuelo => Id}};
        {error, Razon} ->
            {409, #{ok => false, accion => <<"caos">>, error => a_bin(Razon)}}
    end;
ejecutar(<<"fuera_de_orden">>) ->
    case p22_feed:mensaje_fuera_de_orden() of
        {ok, {Id, Respuesta}} ->
            {200, #{ok => true, accion => <<"fuera_de_orden">>,
                    vuelo => Id, resultado => a_bin(Respuesta)}};
        {error, Razon} ->
            {409, #{ok => false, accion => <<"fuera_de_orden">>,
                    error => a_bin(Razon)}}
    end;
ejecutar(<<"pausar">>) ->
    ok = p22_feed:pausar(),
    {200, #{ok => true, accion => <<"pausar">>}};
ejecutar(<<"reanudar">>) ->
    ok = p22_feed:reanudar(),
    {200, #{ok => true, accion => <<"reanudar">>}};
ejecutar(Otra) ->
    {404, #{ok => false,
            error => <<"accion desconocida">>, accion => Otra}}.

%% Respuestas de dominio -> texto para JSON (pueden ser tuplas o atomos).
a_bin(B) when is_binary(B) -> B;
a_bin(A) when is_atom(A) -> atom_to_binary(A, utf8);
a_bin(I) when is_integer(I) -> integer_to_binary(I);
a_bin(T) -> unicode:characters_to_binary(io_lib:format("~p", [T])).
