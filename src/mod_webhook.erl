%%%-------------------------------------------------------------------
%%% @author Srđan Marković <srdjan.markovic@rbt.rs>
%%% @copyright (C) 2020, Red-Black Tree d.o.o.
%%% @doc
%%% Simple module to POST offline messages to a Webhook.
%%% @end
%%% Created: 2020-10-08
%%%-------------------------------------------------------------------
-module(mod_webhook).
-author("srdjan.markovic@rbt.rs").

-behaviour(gen_mod).

-export([start/2, stop/1, reload/3, mod_opt_type/1, mod_options/1, mod_doc/0, depends/2]).
-export([create_message/1, create_message/3]).

-include_lib("xmpp/include/xmpp.hrl").
-include_lib("logger.hrl").
-include_lib("translate.hrl").


%%--------------------------------------------------------------------
%% gen_server callbacks.
%%--------------------------------------------------------------------
-spec start(binary(), gen_mod:opts()) -> {ok, pid()} | {error, term()}.
start(_Host, _Opt) ->
  ?INFO_MSG("mod_webhook loading...", []),
  inets:start(),
  ?INFO_MSG("mod_webhook started", []),
  ejabberd_hooks:add(offline_message_hook, _Host, ?MODULE, create_message, 1).

-spec stop(binary()) -> ok | {error, any()}.
stop(_Host) ->
  ?INFO_MSG("mod_webhook stopping...", []),
  ejabberd_hooks:delete(offline_message_hook, _Host, ?MODULE, create_message, 1).

-spec reload(binary(), gen_mod:opts(), gen_mod:opts()) -> ok | {ok, pid()} | {error, term()}.
reload(_Host, _NewOpts, _OldOpts) ->
  ok.

-spec mod_opt_type(atom()) -> econf:validator().
mod_opt_type(auth_token) ->
  econf:binary();
mod_opt_type(post_url) ->
  econf:binary();
mod_opt_type(confidential) ->
  econf:bool().

-spec mod_options(binary()) -> [{confidential, boolean()} | {atom(), any()}].
mod_options(_Host) ->
  [{auth_token, <<"secret">>},
    {post_url, <<"http://localhost:5000/notify">>},
    {confidential, false}].

mod_doc() ->
  #{desc =>
  ?T("Simple module to POST offline messages to a Webhook endpoint."),
    opts => [
      {auth_token, #{value => "Text", desc => ?T("Authorization Header to be sent with the POST request. "
      "Default value is: \"secret\". Please change to something more secure.")}},
      {post_url, #{value => "Text", desc => ?T("Webhook endpoint URL for the POST request. "
      "Default value is: \"http://localhost:5000/notify\". Change to your Webhook endpoint URL.")}},
      {confidential, #{value => "true | false", desc => ?T("Confidential mode. "
      "Default value is: 'false'. If set to 'true', message Body will not be sent.")}}],
    example => [
      "modules:",
      "  ...",
      "  mod_webhook:",
      "    auth_token: \"secret\"",
      "    post_url: \"http://localhost:5000/notify\"",
      "    confidential: false",
      "  ...",
      "",
      "modules:",
      "  ...",
      "  mod_webhook:",
      "    auth_token: \"mgFqMZcrLMMccjDFFmMCXZhmP9wKeGtXRVuaiwyYk9\"",
      "    post_url: \"https://api.example.com/notify\"",
      "    confidential: true",
      "  ..."]}.

-spec depends(binary(), gen_mod:opts()) -> [{module(), hard | soft}].
depends(_Host, _Opts) ->
  [].

%%--------------------------------------------------------------------
%% Exported utility functions.
%%--------------------------------------------------------------------
create_message({_Action, Packet} = Acc) when (Packet#message.type == chat) and (Packet#message.body /= []) ->
  [{text, _, Body}] = Packet#message.body,
  post_offline_message(Packet#message.from, Packet#message.to, Body, Packet#message.id),
  Acc;

create_message(Acc) ->
  Acc.

create_message(_From, _To, Packet) when (Packet#message.type == chat) and (Packet#message.body /= []) ->
  Body = fxml:get_path_s(Packet, [{elem, list_to_binary("body")}, cdata]),
  MessageId = fxml:get_tag_attr_s(list_to_binary("id"), Packet),
  post_offline_message(_From, _To, Body, MessageId),
  ok.

%%--------------------------------------------------------------------
%% Internal functions.
%%--------------------------------------------------------------------
post_offline_message(From, To, Body, MessageId) ->
  ?INFO_MSG("mod_webhook handling offline message ~p~n, from ~p to ~p, with body ~p", [MessageId, From, To, Body]),
  FromUser = From#jid.luser,
  ToUser = To#jid.luser,
  Host = To#jid.lserver,
  case gen_mod:get_module_opt(Host, ?MODULE, confidential) of
    true -> Data = string:join(["from=", binary_to_list(FromUser), "&to=", binary_to_list(ToUser),
      "&message_id=", binary_to_list(MessageId)], "");
    false -> Data = string:join(["from=", binary_to_list(FromUser), "&to=", binary_to_list(ToUser),
      "&message_id=", binary_to_list(MessageId), "&body=", binary_to_list(Body)], "")
  end,
  ?DEBUG("mod_webhook data ~p", [Data]),
  Token = gen_mod:get_module_opt(Host, ?MODULE, auth_token),
  ?DEBUG("mod_webhook token ~p", [Token]),
  PostUrl = gen_mod:get_module_opt(Host, ?MODULE, post_url),
  ?DEBUG("mod_webhook post url ~p", [PostUrl]),
  Request = {binary_to_list(PostUrl), [{"Authorization", binary_to_list(Token)}],
    "application/x-www-form-urlencoded", Data},
  ?DEBUG("mod_webhook request ~p", [Request]),
  httpc:request(post, Request, [], []),
  ?INFO_MSG("mod_webhook post request sent", []).
