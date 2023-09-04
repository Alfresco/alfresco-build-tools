FROM python:alpine3.18

WORKDIR /root
ADD requirements.txt .
RUN pip install -r requirements.txt

ADD gen_index_yml.py /usr/bin/

ENTRYPOINT ["python", "/usr/bin/gen_index_yml.py"]
