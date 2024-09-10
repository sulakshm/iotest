all:
	gofmt -s -w main.go
	go build .
