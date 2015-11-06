if [  -n "$1" ] && [ -n "$2" ] ; then
	TIMER_INT_DATA="$1"
	echo "Plotting data from $TIMER_INT_DATA"
	TARGET_CPU_NO="$2"
	echo "$TIMER_INT_DATA contains data collected from total CPU: $TARGET_CPU_NO"
	echo "Plotting the stat to dynticks.png"
else
	echo "Please provide timer interrupt data as arg1 and number of CPUs in the target as arg2"
	exit 1
fi

PLOT_CMD="\"$TIMER_INT_DATA\" using 2 every $TARGET_CPU_NO with linespoints  pointtype 1 title \"CPU0\""
for (( i=1; i < $TARGET_CPU_NO; i++ ))
do
	PLOT_CMD+=", \"$TIMER_INT_DATA\" using 2 every $TARGET_CPU_NO::$i with linespoints  pointtype 1 title \"CPU$i\""
done

gnuplot << EOF
	set terminal png
	set output 'dynticks.png'

	set terminal png size 1920,1080
	#set xdata time
	#set timefmt "%S"
	set xlabel "samples"

	#set autoscale

	set samples 10
	set ylabel "timer_ints/sec"
	#set format y "%s"

	set title "Tickless test: CONFIG_NO_HZ_IDLE"
	set key reverse Left outside
	set grid

	set style data linespoints

	plot $PLOT_CMD
EOF
