package main

import (
	"bufio"
	"bytes"
	"flag"
	"fmt"
	"golang.org/x/sys/unix"
	"io"
	"io/fs"
	"math/rand"
	"os"
	"runtime/debug"
	"strings"
	"sync"
	"syscall"
	"time"
)

type inParams struct {
	size uint64
	sync uint
	q    uint
}

type resultInfo struct {
	tgt string
	e   error
	n   uint64
	off int64
}

type writeRecord struct {
	off int64
	qd  uint
}

type targetInfo struct {
	path  string
	fh    int
	color int
	vi    []writeRecord
	mode  int
}

const (
	testDev    = "/dev/mapper/pwx0-507637469268482126"
	dataInPath = "/var/cores/lns/in"
	NBUFS      = 16
	MAXCOLORS  = 16
)

var (
	p = inParams{size: 5 << 30, sync: 1, q: 64}
	//p    = inParams{size: 16 << 10, sync: 1, q: 1}
	data        [NBUFS][]byte
	journalFile *os.File // fd

	jlock sync.Mutex

	// flags
	verify      = flag.Bool("verify", false, "Enable verify mode")
	dev         = flag.String("dev", testDev, "test device")
	seed        = flag.Int("seed", 0, "data pattern seeding")
	devicesFile = flag.String("targets", "", "load target devices from given file")
	shuffle     = flag.Bool("shuffle", false, "shuffle data color and rebuild targets")
	random      = flag.Bool("random", false, "generate random offsets every iteration")
	flush       = flag.Int("flush", 0, "flush freq, 0 - to disable, otherwise cycle freq")
	single      = flag.Bool("single", false, "keep single fds for syncing")

	journalFilePath = "/var/cores/lns/j.dat"
	gTargets        = map[string]targetInfo{}
	gFlush          = int(0) // global sync freq (iteration cycles)

	rng *rand.Rand
)

func appExit(err error) {
	fmt.Printf("failed with error %v", err)
	debug.PrintStack()
	os.Exit(1)
}

func targetfh(tgt string) int {
	ti, ok := gTargets[tgt]
	if !ok {
		appExit(fmt.Errorf("unknown target %s", tgt))
	}
	return ti.fh
}

func targetcolor(tgt string) int {
	ti, ok := gTargets[tgt]
	if !ok {
		appExit(fmt.Errorf("unknown target %s", tgt))
	}
	return ti.color
}

// reading from hardcoded in0, in1 etc
func prepBuffer(i int) {
	// fmt.Printf("prepBuffer(%d)\n", i)
	in, err := os.ReadFile(fmt.Sprintf("%s/in%d", dataInPath, i))
	if err != nil {
		appExit(err)
	}

	copy(data[i], in)
	if len(in) != 4096 {
		appExit(fmt.Errorf("invalid data buf size"))
	}
}

func writeOut(tgt string, wg *sync.WaitGroup, fh int, off int64, color int, rchan chan resultInfo) {
	defer wg.Done()
	//color := (off / 4096) % NBUFS
	nblocks := len(data[color]) / 4096

	// fmt.Printf("Page write at %d, len %d, color %d\n", off, len(data[color]), color)
	n, err := syscall.Pwrite(fh, data[color], off)
	if err != nil {
		appExit(err)
	}

	if n != len(data[color]) {
		appExit(fmt.Errorf("write size mismatch %d, expected %d", n, len(data[color])))
	}

	// track write record - not synced yet - just inflight writes that are acknowledged without sync
	/*
		outb := []byte(fmt.Sprintf("%s %d %d\n", tgt, off, nblocks))
		jlock.Lock()
		n, err := syscall.Write(int(journalFile.Fd()), outb)
		if err != nil {
			appExit(err)
		} else if n != len(outb) {
			appExit(fmt.Errorf("size mismatch journal"))
		}
		jlock.Unlock()
	*/
	trackDirty(tgt, len(data[color]), &writeRecord{off: off, qd: uint(nblocks)})
	rchan <- resultInfo{tgt: tgt, n: 0, off: off}
}

const (
	DIRTY_THRESHOLD = int(100 * (1 << 20))
)

var (
	gDirty    int
	flush_now bool
	dosync    *sync.Cond
)

func syncer() {
	fmt.Println("background syncer active")
	// wait forever for the signal
	for {
		dosync.L.Lock()
		for !flush_now {
			dosync.Wait()
		}
		flush_now = false
		do_sync_work(0)
		dosync.L.Unlock()
	}
}

func syncInit() {
	dosync = sync.NewCond(&jlock)
	gDirty = 0
	flush_now = false
	go syncer()
}

// called under jlock - so no more locks needed
func trackDirty(tgt string, dbytes int, wrec *writeRecord) {
	dosync.L.Lock()
	gDirty += dbytes
	ti := gTargets[tgt]
	ti.vi = append(ti.vi, *wrec) // collect unstable writes in memory
	gTargets[tgt] = ti
	if gDirty >= DIRTY_THRESHOLD {
		flush_now = true
		gDirty = 0
		dosync.Signal()
	}
	dosync.L.Unlock()
}

func writeOneIter(outerwg *sync.WaitGroup, tgt string, fh int, off int64, color int) {
	defer outerwg.Done()

	wg := sync.WaitGroup{}
	rchan := make(chan resultInfo, p.q)

	for i := uint(0); i < p.q; i++ {
		wg.Add(1)

		go writeOut(tgt, &wg, fh, off+int64(i)*4096, color, rchan)
	}

	wg.Wait()
	close(rchan)
}

func verifyIn(tgt string, wg *sync.WaitGroup, off int64, rchan chan resultInfo) {
	defer wg.Done()
	// color := (off / 4096) % NBUFS
	color := targetcolor(tgt)

	// fmt.Printf("Page write at %d, len %d, color %d\n", off, len(data[color]), color)
	var e error
	in := makeOneBuffer()
	defer freeOneBuffer(in)

	n, err := syscall.Pread(targetfh(tgt), in, off)
	if err != nil {
		appExit(err)
	}

	if n != len(data[color]) {
		e = fmt.Errorf("short read at off %d, color %d, got %d", off, color, n)
	} else if !bytes.Equal(in, data[color]) {
		e = fmt.Errorf("read data failed checksum, at off %d, color %d", off, color)
	}

	if e != nil {
		fmt.Printf("writing data out for mismatched checksum at off %d\n",
			off)
		outRecord := fmt.Sprintf("/var/cores/lns/tgt-%s-d%d.bin", tgt, off)
		if err := os.WriteFile(outRecord, in, 0644); err != nil {
			appExit(fmt.Errorf("writing corrupt file(%s) failed at %d",
				outRecord))
		}
	}

	r := resultInfo{tgt: tgt, n: uint64(n), off: off, e: e}
	// fmt.Printf("wrote result record %+v", r)
	rchan <- r
}

func verifyOneIter(tgt string, off int64, q uint) {
	// fmt.Printf("starting verify at %d, q %d\n", off, q)
	wg := sync.WaitGroup{}
	rchan := make(chan resultInfo, p.q)

	for i := uint(0); i < q; i++ {
		wg.Add(1)

		go verifyIn(tgt, &wg, off+int64(i)*4096, rchan)
	}

	wg.Wait()
	close(rchan)

	die := false
	for r := range rchan {
		// fmt.Printf("got result record %+v", r)
		if r.e != nil {
			die = true
			fmt.Errorf("%s: verify failed: %v", tgt, r.e)
		}
	}

	if die {
		appExit(fmt.Errorf("%s: checksum failed at off %d", tgt, off))
	}
}

func buildCtxToVerify(tgt string, off int64, qd uint) {
	if *flush == 0 {
		// unstable write mode check - no fsync from app still verifying
		verifyOneIter(tgt, off, qd)
		return
	}

	ti := gTargets[tgt] // verify info for each target
	if qd == 0 {
		// got a sync record for this device
		for _, rec := range ti.vi {
			verifyOneIter(tgt, rec.off, rec.qd)
		}
		ti.vi = []writeRecord{}
		gTargets[tgt] = ti
		return
	}

	ti.vi = append(ti.vi, writeRecord{off: off, qd: qd})
	gTargets[tgt] = ti
}

func do_verify() {
	jlog, err := os.Open(journalFilePath)
	if err != nil {
		appExit(err)
	}
	defer jlog.Close()

	scanner := bufio.NewScanner(jlog)

	if *flush == 0 {
		fmt.Printf("unstable write verification\n")
	}

	var tgt string
	var off int64
	var q uint
	for scanner.Scan() {
		input := strings.TrimSpace(scanner.Text())
		if len(input) == 0 {
			continue
		}
		n, err := fmt.Sscanf(input, "%s %d %d", &tgt, &off, &q)
		if err != nil {
			appExit(fmt.Errorf("parse failure %s, err %v", input, err))
		}
		if n != 3 {
			appExit(fmt.Errorf("incomplete journal %s - quitting\n", input))
		}
		//verifyOneIter(tgt, off, q)
		buildCtxToVerify(tgt, off, q)
	}

	fmt.Println("verify done")
	os.Exit(0)
}

func makeOneBuffer() []byte {
	// Size of the buffer, and alignment (usually 4096 for O_DIRECT)
	size := 4096
	fd := -1 // We're not mapping a file, just anonymous memory
	prot := unix.PROT_READ | unix.PROT_WRITE
	flags := unix.MAP_PRIVATE | unix.MAP_ANONYMOUS

	buf, err := unix.Mmap(fd, 0, size, prot, flags)
	if err != nil {
		appExit(fmt.Errorf("Error in Mmap: %v\n", err))
	}

	return buf
}

func freeOneBuffer(in []byte) {
	// Unmap when done
	err := unix.Munmap(in)
	if err != nil {
		fmt.Printf("Error in Munmap: %v\n", err)
	}
}

func setupBuffer() {
	for i := 0; i < NBUFS; i++ {
		// Allocate aligned memory using unix.Mmap
		data[i] = makeOneBuffer()
	}
}

func cleanupBuffer() {
	for i := 0; i < NBUFS; i++ {
		// Unmap when done
		freeOneBuffer(data[i])
	}
}

func loadTargets() {
	gTargets = make(map[string]targetInfo)

	if *devicesFile == "" {
		// load defaults
		path := *dev
		mode := unix.O_RDWR | unix.O_DIRECT
		if fi, err := os.Stat(path); err != nil {
			appExit(err)
		} else if fi.Mode()&fs.ModeDevice == 0 {
			fmt.Printf("%s is not a block device\n", path)
			if !*verify {
				mode = unix.O_RDWR | unix.O_CREAT
			} else {
				mode = unix.O_RDWR
			}
			//appExit(fmt.Errorf("bad block device %s", path))
		}
		fh, err := unix.Open(path, mode, 0644)
		//fh, err := unix.Open(path, unix.O_RDWR|unix.O_DIRECT, 0644)
		if err != nil {
			appExit(err)
		}
		gTargets["def"] = targetInfo{path: path, fh: fh, color: *seed, mode: mode}
		return
	}

	// dev path color(0-15)
	// 1124864597118850913 /dev/mapper/pwx0-1124864597118850913 2
	targets, err := os.Open(*devicesFile)
	if err != nil {
		appExit(err)
	}
	defer targets.Close()

	scanner := bufio.NewScanner(targets)

	var dev string
	var path string
	var color int
	for scanner.Scan() {
		input := strings.TrimSpace(scanner.Text())
		if len(input) == 0 {
			continue
		}
		n, err := fmt.Sscanf(input, "%s %s %d", &dev, &path, &color)
		if err != nil {
			if err == io.EOF {
				break
			}
			appExit(fmt.Errorf("parse failure %s, err %v", input, err))
		}
		if n != 3 {
			appExit(fmt.Errorf("incomplete targets %s - quitting\n", input))
		}

		fmt.Printf("target %s, path %s, color %d\n", dev, path, color)

		mode := unix.O_RDWR | unix.O_DIRECT
		if fi, err := os.Stat(path); err != nil {
			appExit(err)
		} else if fi.Mode()&fs.ModeDevice == 0 {
			fmt.Printf("%s is not a block device\n", path)
			//appExit(fmt.Errorf("bad block device %s", path))
			if !*verify {
				mode = unix.O_RDWR | unix.O_CREAT
			} else {
				mode = unix.O_RDWR
			}
		}
		//fh, err := unix.Open(path, unix.O_RDWR|unix.O_DIRECT, 0644)
		fh, err := unix.Open(path, mode, 0644)
		if err != nil {
			appExit(err)
		}
		if color > 15 || color < 0 {
			color = *seed // write default if out of bounds
		}
		fmt.Printf("tgt %s: using color %d\n", dev, color)
		gTargets[dev] = targetInfo{path: path, fh: fh, color: color, mode: mode}
	}
}

func clearTargets() {
	for _, ti := range gTargets {
		if ti.fh >= 0 {
			unix.Close(ti.fh)
		}
	}
}

func do_shuffle() {
	gTargets = make(map[string]targetInfo)

	if *devicesFile == "" {
		fmt.Printf("shuffle data color only when targets file is available - no work")
		return
	}

	// dev path color(0-15)
	// 1124864597118850913 /dev/mapper/pwx0-1124864597118850913 2
	targets, err := os.OpenFile(*devicesFile, os.O_RDWR, 0644)
	if err != nil {
		appExit(err)
	}
	defer targets.Close()

	scanner := bufio.NewScanner(targets)

	var dev string
	var path string
	var color int
	for scanner.Scan() {
		input := strings.TrimSpace(scanner.Text())
		if len(input) == 0 {
			continue
		}
		n, err := fmt.Sscanf(input, "%s %s %d", &dev, &path, &color)
		if err != nil {
			if err == io.EOF {
				break
			}
			appExit(fmt.Errorf("parse failure %s, err %v", input, err))
		}
		if n != 3 {
			appExit(fmt.Errorf("incomplete targets %s - quitting\n", input))
		}

		for {
			newColor := rng.Intn(MAXCOLORS)
			if newColor == color {
				continue
			}
			color = newColor
			break
		}
		fmt.Printf("shuffled->target %s, path %s, color %d\n", dev, path, color)
		gTargets[dev] = targetInfo{path: path, color: color}
	}

	var outb []byte
	//outb := make([]byte, 4096)
	for tag, ti := range gTargets {
		// write tag, ti.path ti.color
		outb = append(outb, []byte(fmt.Sprintf("%s %s %d\n", tag, ti.path, ti.color))...)
	}
	targets.Seek(0, 0)
	if _, err := targets.Write(outb); err != nil {
		appExit(err)
	}
	if err := targets.Sync(); err != nil {
		appExit(err)
	}
}

// called under journal lock
func do_sync_work(curOff int64) {
	type tgtPathInfo struct {
		path string
		mode int
		fh   int
		skip bool // skip sync
	}
	dirtyMap := make(map[string][]writeRecord)
	tgtFhMap := make(map[string]tgtPathInfo)
	// writeout unstable journal recs
	for tgt, ti := range gTargets {
		dirtyMap[tgt] = ti.vi
		ti.vi = []writeRecord{}
		gTargets[tgt] = ti

		tgtFhMap[tgt] = tgtPathInfo{path: ti.path, mode: ti.mode, fh: ti.fh}
	}
	jlock.Unlock()

	for tgt, wrecs := range dirtyMap {
		outb := []byte{}
		for _, wrec := range wrecs {
			outb = append(outb, []byte(fmt.Sprintf("%s %d %d\n", tgt, wrec.off, wrec.qd))...)
		}
		if len(outb) == 0 {
			rec := tgtFhMap[tgt]
			rec.skip = true
			tgtFhMap[tgt] = rec
			continue
		}
		jlock.Lock()
		// single update of all unstable records
		n, err := syscall.Write(int(journalFile.Fd()), outb)
		if err != nil {
			appExit(err)
		} else if n != len(outb) {
			appExit(fmt.Errorf("size mismatch journal"))
		}
		jlock.Unlock()
	}

	// do the sync outside jlock
	outb := []byte{}
	for tgt, ti := range tgtFhMap {
		if ti.skip {
			continue
		}
		localfd := ti.fh
		if !*single {
			newfd, err := unix.Open(ti.path, ti.mode, 0644)
			if err != nil {
				appExit(err)
			}
			localfd = newfd
		}
		if err := syscall.Fsync(localfd); err != nil {
			appExit(err)
		}
		if !*single {
			unix.Close(localfd)
		}
		outb = append(outb, []byte(fmt.Sprintf("%s %d 0\n", tgt, curOff))...)
	}

	jlock.Lock()
	// write sync record - this tracks unstable writes above
	n, err := syscall.Write(int(journalFile.Fd()), outb)
	if err != nil {
		appExit(err)
	} else if n != len(outb) {
		appExit(fmt.Errorf("size mismatch journal"))
	}
	gFlush = *flush
}

func main() {
	var err error

	flag.Parse()
	if *seed > 15 || *seed < 0 {
		fmt.Printf("seed(%d) out of bounds, reset to 0\n", *seed)
		*seed = 0
	}

	rng = rand.New(rand.NewSource(time.Now().UnixNano()))

	if *shuffle {
		do_shuffle()
		os.Exit(0)
	}

	loadTargets()
	defer clearTargets()

	setupBuffer()
	defer cleanupBuffer()
	for i := 0; i < 16; i++ {
		prepBuffer(i)
	}

	// Open journal file for appending log entries
	//journalFilePath = fmt.Sprintf("/var/cores/lns/j-%s.dat", path.Base(*dev))
	fmt.Printf("using journal %s\n", journalFilePath)
	if !*verify {
		fmt.Printf("new run - deleting last journal %s\n", journalFilePath)
		os.Remove(journalFilePath)
	}
	journalFile, err = os.OpenFile(journalFilePath, os.O_WRONLY|os.O_CREATE|os.O_APPEND|os.O_SYNC, 0644)
	if err != nil {
		appExit(err)
	}
	defer func() { journalFile.Close() }()
	fmt.Printf("journal opened at %v\n", journalFile.Fd())

	if *verify {
		do_verify()
	}

	// kick start syncer only in write phase
	syncInit()

	nWrites := p.size / 4096
	nIterations := int64(nWrites / uint64(p.q))
	gFlush = *flush

	// starting off
	off := rand.Int63n(nIterations)
	byteOff := off * 4096 * int64(p.q)
	for iter := int64(0); iter < nIterations; iter++ {
		wg := sync.WaitGroup{}
		// IO to all devices in parallel
		for tgt, ti := range gTargets {
			wg.Add(1)
			go writeOneIter(&wg, tgt, ti.fh, byteOff, ti.color)
		}
		wg.Wait()

		// covered upto this offset on all devices this iteration
		byteOff += (4096 * int64(p.q))

		// write journal out tuple <off q> if enabled
		/*
			if gFlush > 0 {
				gFlush--
				if gFlush == 0 {
					// covered upto byteOff += (4096 * int64(p.q))
					do_sync_work(byteOff)
				}
			}
		*/

		if *random {
			// can overwrite
			byteOff = rand.Int63n(nIterations) * 4096 * int64(p.q)
		} else {
			// sequential - continue from where we left off next cycle
			if uint64(byteOff) >= p.size {
				byteOff = 0
			}
		}
	}

	fmt.Println("Write operation and journaling completed successfully.")
}
