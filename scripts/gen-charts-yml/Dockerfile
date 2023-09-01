FROM python:alpine3.18

WORKDIR /root
ADD requirements.txt .
RUN pip install -r requirements.txt

ADD gen_charts_yml.py /usr/bin/

ENTRYPOINT ["python", "/usr/bin/gen_charts_yml.py"]
