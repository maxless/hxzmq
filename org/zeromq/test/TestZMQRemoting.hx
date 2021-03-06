/**
 * (c) 2011 Richard J Smith
 *
 * This file is part of hxzmq
 *
 * hxzmq is free software; you can redistribute it and/or modify it under
 * the terms of the Lesser GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * hxzmq is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * Lesser GNU General Public License for more details.
 *
 * You should have received a copy of the Lesser GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package org.zeromq.test;

import haxe.remoting.AsyncProxy;
import haxe.remoting.Context;
import haxe.io.Bytes;
import haxe.remoting.Proxy;
import neko.Sys;
import org.zeromq.ZContext;
import org.zeromq.ZFrame;
import org.zeromq.ZMsg;
import org.zeromq.ZSocket;

#if !php
import neko.vm.Thread;
#end
import org.zeromq.remoting.ZMQConnection;
import org.zeromq.ZMQ;
import org.zeromq.ZMQSocket;
import org.zeromq.test.helpers.HelloWorldResponderAPI;

import org.zeromq.test.BaseTest;

class TestZMQRemoting extends BaseTest
{

    
    static inline var TESTSTRING = "Hello World";
    
    /**
     * This test creates 2 threads, "sender" and "responder" which communicate with each other 
     * using haXe remoting via ZMQ REQ-REP inproc sockets.
     * 
     * "sender" calls HelloWorldResponderAPI.hello() via haxe remoting 
     * (first time via call method, 2nd time via proxy object).
     * 
     * "receiver" picks up the message, passes it to the remoting context to process,
     * which calls the hello() method on an HelloWorldResponderAPI object.
     * 
     * The context sends an answer "Bill, Hello World" back to the sender thread via the ZMQ REP socket.
     * 
     * The "sender" thread receives the answer msg, calls the ZMQConnection.processMessage) method, 
     * which calls the display() callback, which sends the answer back to the main thread 
     * (via haxe thread sendMessage / readMessage) for assertion in the test case.
     * 
     * Finally, the "sender" thread sends direct  "quit" string messages to the responder thread (via ZMQ) 
     * and the main thread (via haxe thread messaging), which cause them to close the ZMQ sockets gracefully.
     * Also demonstrates how the ZMQ sockets could be used for remoting calls and any other message traffic.
     *
     */
    public function testThreadedRemotingSendResponse() {
        
#if php
		// Skip test involving threads for php target
        assertTrue(true);
#else        
        var responderThread:Thread = Thread.create(helloWorldResponder);
        var senderThread:Thread = Thread.create(helloWorldSender);
        
        // Send reference to main thread to sender thread.
        // This also triggers the sender thread to send a remoting api call to the responder
        senderThread.sendMessage(Thread.current());
        
        var res = null;
        while (true) {
            // Wait for result back from sender thread
            var res = Thread.readMessage(true);
            //trace ("main thread received:" + res);
            assertTrue(Std.is(res, String));
            
            if (res == "quit") {
                // test complete
                break;
            }
            assertEquals("Bill, "+TESTSTRING, res);
        }
 #end 
    }
    
    /**
     * This method repeats the previous test but using a single thread and with tcp transport
     */
    public function testSynchronousRemotingSendResponse() {
		var ZMQcontext:ZContext = new ZContext();
		
        var pair:SocketPair;
		// Create pair of ZMQSockets managed by the ZContext object.
		pair = { s1: ZMQcontext.createSocket(ZMQ_REQ), s2: ZMQcontext.createSocket(ZMQ_REP) };
		var s1Port = ZSocket.bindEndpoint(pair.s1, "tcp", "127.0.0.1", "*");
		ZSocket.connectEndpoint(pair.s2, "tcp", "127.0.0.1", Std.string(s1Port));

		// Socket to talk to responder
		var sender:ZMQSocket = pair.s1;
		// Socket to talk to sender
		var responder:ZMQSocket = pair.s2;

        // Set up haXe remoting context and add remote-callable methods
        var remotingContext:Context = new Context();
        remotingContext.addObject("HelloWorldResponder", new HelloWorldResponderAPI());
		var conn:ZMQConnection = ZMQConnection.create(responder, remotingContext);
        
        var cnx:ZMQConnection = ZMQConnection.create(sender);
        // setup error handler
        cnx.setErrorHandler( function(err) trace("Error : "+Std.string(err)) );
        
        var me = this;       

        // test 1. Use direct, untyped "call"
        // Send request to responder via a ZMQConnection call
        cnx.HelloWorldResponder.hello.call(["Bill"], function(s:String) {
            me.assertEquals(s, "Bill, Hello World");
        });
        
        // Wait for next request from client
        var d = conn.getProtocol().readMessage();
        conn.processMessage(d);

        // Wait for reply back
		var rep:ZFrame = ZFrame.recvFrame(sender);
        cnx.processMessage(rep.toString());       
    }
#if (neko || cpp)    
    static function helloWorldSender() {
		var context:ZMQContext = ZMQContext.instance();

		// Socket to talk to responder
		var sender:ZMQSocket = context.socket(ZMQ_REQ);
		sender.connect("inproc://remoting");

        // Wait for start trigger from main thread
        var main:Thread = Thread.readMessage(true);
        
        // Set callback
        var display = function(s:String) {
            // send result back to main thread using haxe thread messaging
             main.sendMessage(s);
        }
	
        var cnx:ZMQConnection = ZMQConnection.create(sender);
        // setup error handler
        cnx.setErrorHandler( function(err) trace("Error : "+Std.string(err)) );

        try {
            // test 1. Use direct, untyped "call" using ZFrame to receive remoting request response
            // Send request to responder via a ZMQConnection call
            cnx.HelloWorldResponder.hello.call(["Bill"], display);
            // Wait for reply 
            // Wait for reply back
            var rep:Bytes = sender.recvMsg();
            //trace ("sender received message:" + rep.toString());
            cnx.processMessage(rep.toString());
                      
            // test 2. Use remoting proxy class using ZFrame to receive remoting request response
            // Send request to responder via a ZMQConnection call
            var proxy:HelloWorldResponderAPIProxy = new HelloWorldResponderAPIProxy(cnx.HelloWorldResponder);
            proxy.hello("Bill");
            // Wait for reply back
            var rep:Bytes = sender.recvMsg();
            cnx.processMessage(rep.toString());
            
            // Now tell responder to quit, by sending a direct ZMQ message
            sender.sendMsg(Bytes.ofString("quit"));
            
            // Shut down sender socket
            sender.close();
            
            // Wait for responder thread to receive the quit message before terminating the main test thread
            Sys.sleep(0.1);
            
            // Then tell main thread to quit test
            main.sendMessage("quit");
            
		} catch (e:ZMQException) {
				if (!ZMQ.isInterrupted()) {
                    trace (e.toString());
				}
		}
           

        
    }
    
    static function helloWorldResponder() {
		var context:ZMQContext = ZMQContext.instance();

		// Socket to talk to sender
		var responder:ZMQSocket = context.socket(ZMQ_REP);
		responder.bind("inproc://remoting");

        // Set up haXe remoting context and add remote-callable methods
        var ctx:Context = new Context();
        ctx.addObject("HelloWorldResponder", new HelloWorldResponderAPI());
		var conn:ZMQConnection = ZMQConnection.create(responder, ctx);
		ZMQ.catchSignals();
		
        try {
            while (true) {
                // Wait for next request from client
                var d = conn.getProtocol().readMessage();
                //trace ("responder received message:" + d);
                if (d == "quit") {
                    break;
                } else {
                    conn.processMessage(d);
                }
            }
        } catch (e:ZMQException) {
            trace (e.toString());
        }
        
		responder.close();
		return null;
        
    }
#end
}


class HelloWorldResponderAPIProxy extends AsyncProxy<org.zeromq.test.helpers.HelloWorldResponderAPI> { }
