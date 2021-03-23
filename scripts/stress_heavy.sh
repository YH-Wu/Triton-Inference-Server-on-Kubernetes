#/bin/sh
i=0
URL=<TRITON_EXTERNAL_IP>
BATCH_SIZE=32
while :
do
        echo "Loop $i, sending $BATCH_SIZE requests to Triton Inference Server"
        /workspace/install/bin/image_client -m inception_graphdef -c 1 -s INCEPTION /workspace/images/mug.jpg -u $URL:8000 -b $BATCH_SIZE >> /dev/null &
        /workspace/install/bin/image_client -m inception_graphdef -c 1 -s INCEPTION /workspace/images/mug.jpg -u $URL:8000 -b $BATCH_SIZE >> /dev/null &        
        sleep 0.5
        i=$(($i+1))
done

