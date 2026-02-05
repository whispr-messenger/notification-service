#Test local

test local d'un message notification :OK
iex.bat -S mix   
Erlang/OTP 28 [erts-16.2] [source] [64-bit] [smp:12:12] [ds:12:12:10] [async-threads:1] [jit:ns]

    warning: function maybe_retry/1 is unused
    │
 33 │   defp maybe_retry(attempt) do
    │        ~
    │
    └─ lib/whispr_notifications/delivery/batch_processor.ex:33:8: WhisprNotifications.Delivery.BatchProcessor (module)

Interactive Elixir (1.19.5) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> alias WhisprNotifications.Events.MessageEvents
WhisprNotifications.Events.MessageEvents
iex(2)> MessageEvents.handle_new_message(%{                                                                                                                                                                                
          user_id: "user-123",                                                                                                                                                                                             
          conversation_id: "conv-1",                                                                                                                                                                                       
          message_id: "msg-1",                                                                                                                                                                                             
          sender_id: "user-999",                                                                                                                                                                                           
          manager_id: "manager-42",                                                                                                                                                                                        
          preview: "Salut, ça va ?"                                                                                                                                                                                        
        })                                                                                                                                                                                                                 
:ok