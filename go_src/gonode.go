package main

import (
	"bufio"
	"flag"
	"fmt"
	"github.com/goerlang/etf"
	"github.com/goerlang/node"
	"log"
	"os"
)

type srv struct {
	node.GenServerImpl
	completeChan chan bool
}

var SrvName string
var NodeName string
var LogFile string
var Cookie string
var err error
var EpmdPort int
var EnableRPC bool
var PidFile string

func init() {
	flag.StringVar(&LogFile, "log", "", "log file. if not setted then output on console")
	flag.StringVar(&SrvName, "gen_server", "go_srv", "gonode gen_server name")
	flag.StringVar(&NodeName, "name", "gonode@localhost", "gonode node name")
	flag.StringVar(&Cookie, "cookie", "123", "cookie for gonode for interaction with erlang node")
	flag.IntVar(&EpmdPort, "epmd_port", 5588, "epmd port")
	flag.BoolVar(&EnableRPC, "rpc", false, "enable RPC")
	flag.StringVar(&PidFile, "pid_file", "", "pid file path")
}

func main() {
	// Parse CLI flags
	flag.Parse()

	setup_logging()
	write_pid()

	log.Println("node started")

	// Initialize new node with given name and cookie
	enode := node.NewNode(NodeName, Cookie)

	// Allow node be available on EpmdPort port
	err = enode.Publish(EpmdPort)
	if err != nil {
		log.Fatalf("Cannot publish: %s", err)
	}

	// Create channel to receive message when main process should be stopped
	completeChan := make(chan bool)

	// Initialize new instance of srv structure which implements Process behaviour
	eSrv := new(srv)

	// Spawn process with one arguments
	enode.Spawn(eSrv, completeChan)

	// RPC
	if EnableRPC {
		// Create closure
		eClos := func(terms etf.List) (r etf.Term) {
			r = etf.Term(etf.Tuple{etf.Atom("gonode"), etf.Atom("reply"), len(terms)})
			return
		}

		// Provide it to call via RPC with `rpc:call(gonode@localhost, go_rpc, call, [as, qwe])`
		err = enode.RpcProvide("go_rpc", "call", eClos)
		if err != nil {
			log.Printf("Cannot provide function to RPC: %s", err)
		}
	}

	// Wait to stop
	<-completeChan

	log.Println("node finished")

	return
}

// Init
func (gs *srv) Init(args ...interface{}) {
	log.Printf("Init: %#v", args)

	// Self-registration with name go_srv
	gs.Node.Register(etf.Atom("go_srv"), gs.Self)

	// Store first argument as channel
	gs.completeChan = args[0].(chan bool)
}

// HandleCast
// Call `gen_server:cast({go_srv, gonode@localhost}, stop)` at Erlang node to stop this Go-node
func (gs *srv) HandleCast(message *etf.Term) {
	log.Printf("HandleCast: %#v", *message)

	// Check type of message
	switch req := (*message).(type) {
	case etf.Tuple:
		if len(req) > 0 {
			switch act := req[0].(type) {
			case etf.Atom:
				if string(act) == "ping" {
					var self_pid etf.Pid = gs.Self
					gs.Node.Send(req[1].(etf.Pid), etf.Tuple{etf.Atom("pong"), etf.Pid(self_pid)})
				}
			}
		}
	case etf.Atom:
		// If message is atom 'stop', we should say it to main process
		if string(req) == "stop" {
			gs.completeChan <- true
		}
	}
}

// HandleCall
// Call `gen_server:call({go_srv, gonode@localhost}, Message)` at Erlang node
func (gs *srv) HandleCall(message *etf.Term, from *etf.Tuple) (reply *etf.Term) {
	log.Printf("HandleCall: %#v, From: %#v", *message, *from)

	// Just create new term tuple where first element is atom 'ok', second 'go_reply' and third is original message
	replyTerm := etf.Term(etf.Tuple{etf.Atom("ok"), etf.Atom("go_reply"), *message})
	reply = &replyTerm
	return
}

// HandleInfo
func (gs *srv) HandleInfo(message *etf.Term) {
	log.Printf("HandleInfo: %#v", *message)
}

// Terminate
func (gs *srv) Terminate(reason interface{}) {
	log.Printf("Terminate: %#v", reason.(int))
}

func setup_logging() {
	// Enable logging only if setted -log option
	if LogFile != "" {
		var f *os.File
		if f, err = os.Create(LogFile); err != nil {
			log.Fatal(err)
		}
		log.SetOutput(f)
	}
}

func write_pid() {
	log.Println("process pid:", os.Getpid())
	if PidFile != "" {
		file, err := os.Create(PidFile)
		if err != nil {
			log.Fatal(err)
		}
		defer file.Close()
		w := bufio.NewWriter(file)
		fmt.Fprintf(w, "%v", os.Getpid())
		w.Flush()
		log.Println("write pid in", PidFile)
	}
}
