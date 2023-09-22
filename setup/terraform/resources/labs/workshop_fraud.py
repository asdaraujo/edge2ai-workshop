#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Common utilities for Python scripts
"""
import tempfile
from nipyapi import canvas, versioning, nifi, parameters
from nipyapi.nifi.rest import ApiException

from . import *
from .utils import schreg, nifireg, nifi as nf, kafka, kudu, cdsw, impala, ssb, smm, dataviz

PG_NAME = 'Fraud Detection'
REGISTRY_BUCKET_NAME = 'FraudFlow'

_TRANSACTION_SCHEMA_URI = 'https://gist.githubusercontent.com/asdaraujo/e680557100b82d5e0004d7b9f4e3b4f7/raw' \
                          '/f7192cb27e61035fa26156881980342bf385fd2f/transaction.avsc'
TRUSTSTORE_PATH = '/opt/cloudera/security/jks/truststore.jks'
KAFKA_PROVIDER_NAME = 'edge2ai-kafka'
KUDU_CATALOG_NAME = 'edge2ai-kudu'

TOPICS = ['transactions']

GEN_TXN_SCRIPT = '''import json
import math
import random
import sys
import time
import uuid
from datetime import datetime, timedelta
from java.lang import Throwable
from org.apache.nifi.components import PropertyDescriptor
from org.apache.nifi.processor import Processor, Relationship
from org.apache.nifi.processor.io import OutputStreamCallback
from org.apache.nifi.processor.util import StandardValidators
from org.python.core import PySet
from org.apache.nifi.components import ValidationResult

CITIES_DEFAULT = [
    {'lat': -37.7944514, 'lon': 144.904883, 'city': 'Melbourne'},
    {'lat': -33.7761271, 'lon': 150.8851715, 'city': 'Sydney'},
    {'lat': -32.0396959, 'lon': 115.8214564, 'city': 'Perth'},
    {'lat': -35.2813003, 'lon': 149.1270107, 'city': 'Canberra'},
    {'lat': -27.3817681, 'lon': 152.8531169, 'city': 'Brisbane'},
    {'lat': -35.0004053, 'lon': 138.4710808, 'city': 'Adelaide'},
    {'lat': -36.859653, 'lon': 174.6360824, 'city': 'Auckland'},
    {'lat': -41.2730169, 'lon': 174.8563103, 'city': 'Wellington'},
    {'lat': -43.5510444, 'lon': 172.5130723, 'city': 'Christchurch'},
    {'lat': -44.9967799, 'lon': 168.6647798, 'city': 'Queenstown'},
]


class PyOutputStreamCallback(OutputStreamCallback):
  def __init__(self, content=None):
      self._content = content

  def process(self, outputStream):
      outputStream.write(bytearray(self._content.encode('utf-8')))

  def content(self, content):
      self._content = content
      return self


class FraudGeneratorProcessor(Processor):
    PROP_FRAUD_FREQ_MIN = (PropertyDescriptor.Builder()
        .name('fraud-freq-min')
        .displayName('Fraud frequency minimum (ticks)')
        .description('Lower bound for the range of fraud frequency.')
        .expressionLanguageSupported(True)
        .required(True)
        .defaultValue('5')
        .addValidator(StandardValidators.NUMBER_VALIDATOR)
        .build())
    PROP_FRAUD_FREQ_MAX = (PropertyDescriptor.Builder()
        .name('fraud-freq-max')
        .displayName('Fraud frequency maximum (ticks)')
        .description('Upper bound for the range of fraud frequency.')
        .expressionLanguageSupported(True)
        .required(True)
        .defaultValue('15')
        .addValidator(StandardValidators.NUMBER_VALIDATOR)
        .build())
    PROP_CITIES = (PropertyDescriptor.Builder()
        .name('cities')
        .displayName('Cities')
        .description('List of cities in JSON format. Each city is an object with the following attributes: lat, lon, city.')
        .expressionLanguageSupported(True)
        .required(True)
        .defaultValue(json.dumps(CITIES_DEFAULT, indent=2))
        .addValidator(StandardValidators.NON_EMPTY_VALIDATOR)
        .build())

    def __init__(self):
        self.REL_SUCCESS = Relationship.Builder().name('success').description('FlowFiles that were successfully processed').build()
        self.log = None
        self.out = None
        self.cities = None
        self.fraud_countdown = None

    def initialize(self, context):
        self.log = context.getLogger()
        self.out = PyOutputStreamCallback()

    def getRelationships(self):
        return PySet([self.REL_SUCCESS])

    def validate(self, context):
        try:
            json.loads(context.getProperty(self.PROP_CITIES).getValue())
        except Exception as exc:
            error = (ValidationResult.Builder()
                .subject('Cities')
                .valid(False)
                .explanation('it is not a valid JSON')
                .build())
            return [error]
        return None

    def getPropertyDescriptors(self):
        return [self.PROP_CITIES, self.PROP_FRAUD_FREQ_MIN, self.PROP_FRAUD_FREQ_MAX]

    def onPropertyModified(self, descriptor, oldValue, newValue):
        pass

    def getIdentifier(self):
        return None

    def onTrigger(self, context, sessionFactory):
        session = sessionFactory.createSession()
        self.cities = self._get_cities(context)
        self._update_fraud_countdown(context)
        try:
            tx = self._create_transaction()
            self._send_transaction(session, tx)
            if self._should_generate_fraud():
                fraud_tx = self._create_transaction(tx, random.randint(60,600))
                self._send_transaction(session, fraud_tx)
            session.commit()
        except Throwable, t:
            self.log.error('{} failed to process due to {}; rolling back session', [self, t])
            session.rollback(true)
            raise t

    def _send_transaction(self, session, tx):
        flowfile = session.create()
        flowfile = session.putAttribute(flowfile, 'fraud_countdown', str(self.fraud_countdown))
        flowfile = session.write(flowfile, self.out.content(json.dumps(tx)))
        session.transfer(flowfile, self.REL_SUCCESS)

    def _create_random_point(self, x0, y0, distance):
        r = distance/111300
        u = random.random()
        v = random.random()
        w = r * math.sqrt(u)
        t = 2 * math.pi * v
        x = w * math.cos(t)
        x1 = x / math.cos(y0)
        y = w * math.sin(t)
        return (x0+x1, y0 +y)

    def _create_geopoint(self, lat, lon):
        return self._create_random_point(lat, lon, 50000)

    def _get_latlon(self):
        geo = random.choice(self.cities)
        return self._create_geopoint(geo['lat'], geo['lon'])

    def _create_transaction(self, orig_tx=None, delta_secs=0):
        """Creates a single financial transaction using the following
        """
        latlon = self._get_latlon()
        ts = (datetime.now() - timedelta(seconds=delta_secs)).strftime('%Y-%m-%d %H:%M:%S')
        return {
          'ts': ts,
          'account_id': orig_tx['account_id'] if orig_tx else str(random.randint(1, 1000)),
          'transaction_id': ('xxx' + orig_tx['transaction_id']) if orig_tx else str(uuid.uuid1()),
          'amount': random.randrange(1,2000),
          'lat': latlon[0],
          'lon': latlon[1]
        }

    def _create_fraudtran(self, tx, delta_time):
        """Creates a single fraudulent financial transaction
        Note: the fraudulent transaction will have the same account ID as
        the original transaction but different location and ammount.
        """
        latlon = get_latlon()
        tsbis = str((datetime.now() - timedelta(seconds=random.randint(60,600))).strftime('%Y-%m-%d %H:%M:%S '))

        fraudtran = {
          'ts' : tsbis,
          'account_id' : fintran['account_id'],
          'transaction_id' : 'xxx' + str(fintran['transaction_id']),
          'amount' : random.randrange(1,2000),
          'lat' : latlon[0],
          'lon' : latlon[1]
        }
        return (fraudtran)

    def _update_fraud_countdown(self, context):
        if self.fraud_countdown is None or self.fraud_countdown <= 0:
            freq_min = int(context.getProperty('fraud-freq-min').getValue())
            freq_max = int(context.getProperty('fraud-freq-max').getValue())
            self.fraud_countdown = random.randint(freq_min, freq_max)
        elif self.fraud_countdown > 0:
            self.fraud_countdown -= 1

    def _should_generate_fraud(self):
        return self.fraud_countdown <= 0

    def _get_cities(self, context):
        cities = context.getProperty('cities').getValue()
        return json.loads(cities)


processor = FraudGeneratorProcessor()
'''

CITIES_DEFAULT = '''[
  { "city": "Melbourne", "lon": 144.904883,"lat": -37.7944514 }, 
  { "city": "Sydney", "lon": 150.8851715, "lat": -33.7761271 }, 
  { "city": "Perth", "lon": 115.8214564, "lat": -32.0396959 }, 
  { "city": "Canberra", "lon": 149.1270107, "lat": -35.2813003 }, 
  { "city": "Brisbane", "lon": 152.8531169, "lat": -27.3817681 }, 
  { "city": "Adelaide", "lon": 138.4710808, "lat": -35.0004053 }, 
  { "city": "Auckland", "lon": 174.6360824, "lat": -36.859653 }, 
  { "city": "Wellington", "lon": 174.8563103, "lat": -41.2730169 }, 
  { "city": "Christchurch", "lon": 172.5130723, "lat": -43.5510444 }, 
  { "city": "Queenstown", "lon": 168.6647798, "lat": -44.9967799 }
]
'''

CREATE_TABLES_STMTS = [
    '''CREATE TABLE IF NOT EXISTS transactions
(
ts string,
acc_id string,
transaction_id string,
amount bigint,
lat double,
lon double,
fraud_score double,
PRIMARY KEY (ts, acc_id)
)
PARTITION BY HASH PARTITIONS 16
STORED AS KUDU
TBLPROPERTIES ('kudu.num_tablet_replicas' = '1');''',
    '''CREATE TABLE IF NOT EXISTS customers
(
acc_id string,
f_name string,
l_name string,
email string,
gender string,
phone string,
card string,
PRIMARY KEY (acc_id)
)
PARTITION BY HASH PARTITIONS 16
STORED AS KUDU
TBLPROPERTIES ('kudu.num_tablet_replicas' = '1')''',
    '''DELETE FROM customers''',
    '''INSERT INTO customers VALUES
('1','Ajay','Suggate','asuggate0@surveymonkey.com','Female','+967-859-929-9803','mastercard'),
('2','Josee','Linger','jlinger1@narod.ru','Male','+33-288-715-3749','visa'),
('3','Annabela','Stainson','astainson2@list-manage.com','Female','+507-839-252-2958','americanexpress'),
('4','Carissa','Alam','calam3@soup.io','Male','+91-485-850-2519','americanexpress'),
('5','Osborne','Cossar','ocossar4@webmd.com','Non-binary','+48-733-834-8418','americanexpress'),
('6','Leigh','Comberbeach','lcomberbeach5@chron.com','Female','+54-621-759-9341','americanexpress'),
('7','Chiquia','Cheson','ccheson6@people.com.cn','Female','+62-152-951-7203','visa'),
('8','Domenico','Ruhben','druhben7@goo.ne.jp','Female','+62-502-581-0325','mastercard'),
('9','Vanessa','Piken','vpiken8@posterous.com','Female','+86-721-126-9574','visa'),
('10','Othilia','Temby','otemby9@google.co.jp','Male','+7-787-194-3912','americanexpress'),
('11','Blair','Youens','byouensa@unc.edu','Male','+98-319-352-9620','mastercard'),
('12','Jarrid','Eck','jeckb@liveinternet.ru','Female','+7-124-591-3885','americanexpress'),
('13','Keriann','Cattrall','kcattrallc@stanford.edu','Female','+387-899-279-0335','americanexpress'),
('14','Elayne','Sich','esichd@cbc.ca','Female','+48-578-942-7973','visa'),
('15','Karlotte','Cory','kcorye@pinterest.com','Male','+86-264-461-1525','americanexpress'),
('16','Verge','Prozescky','vprozesckyf@google.cn','Female','+386-449-845-1554','mastercard'),
('17','Blanch','Plascott','bplascottg@nsw.gov.au','Male','+86-904-446-4216','mastercard'),
('18','Kare','Lightbourn','klightbournh@mit.edu','Male','+351-661-366-4873','visa'),
('19','Glen','Nottram','gnottrami@jimdo.com','Female','+55-213-275-8407','visa'),
('20','Janeta','Featenby','jfeatenbyj@theatlantic.com','Female','+974-755-798-2062','americanexpress'),
('21','Gibb','Hatliffe','ghatliffek@woothemes.com','Male','+86-250-553-1506','visa'),
('22','Boniface','Kleinberer','bkleinbererl@xrea.com','Female','+86-152-664-3072','visa'),
('23','Kellyann','Keeler','kkeelerm@topsy.com','Genderqueer','+48-489-153-8247','visa'),
('24','Gage','Phelp','gphelpn@ft.com','Female','+20-118-657-8815','mastercard'),
('25','Rhys','Glyn','rglyno@marketwatch.com','Female','+62-758-446-7700','visa'),
('26','Maurise','Jeakins','mjeakinsp@ifeng.com','Male','+49-658-144-1923','mastercard'),
('27','Bellina','Hammonds','bhammondsq@jiathis.com','Female','+86-659-606-3679','visa'),
('28','Staffard','Pietraszek','spietraszekr@gmpg.org','Male','+7-339-546-7513','mastercard'),
('29','Edlin','Du Barry','edubarrys@amazon.com','Male','+86-327-556-0318','americanexpress'),
('30','Sayer','Findlow','sfindlowt@scribd.com','Male','+86-178-186-8421','americanexpress'),
('31','Faber','Hughlock','fhughlocku@theatlantic.com','Agender','+55-903-576-3484','visa'),
('32','Doug','Stoneham','dstonehamv@aol.com','Female','+62-824-335-7761','americanexpress'),
('33','Adelind','Dunmore','adunmorew@cdc.gov','Male','+7-115-821-9698','mastercard'),
('34','Viole','Tonepohl','vtonepohlx@com.com','Female','+62-857-551-4933','mastercard'),
('35','Clyde','Vidgen','cvidgeny@booking.com','Female','+62-268-686-5679','americanexpress'),
('36','Josey','Poley','jpoleyz@blogtalkradio.com','Male','+62-926-937-3623','americanexpress'),
('37','Elisabeth','Bizzey','ebizzey10@1688.com','Male','+1-598-664-5053','visa'),
('38','Skell','Hursey','shursey11@biblegateway.com','Female','+55-377-253-7906','mastercard'),
('39','Ricki','Moreton','rmoreton12@paypal.com','Male','+63-746-225-0378','mastercard'),
('40','Gale','Jeavons','gjeavons13@yolasite.com','Female','+7-421-775-2333','mastercard'),
('41','Bryon','Strugnell','bstrugnell14@ucla.edu','Female','+374-590-701-0447','mastercard'),
('42','Granthem','Wedlock','gwedlock15@toplist.cz','Male','+20-444-320-8605','americanexpress'),
('43','Conant','Myton','cmyton16@chron.com','Female','+46-682-217-3034','americanexpress'),
('44','Clotilda','Suche','csuche17@moonfruit.com','Male','+81-856-534-8193','americanexpress'),
('45','Rosalind','Thurby','rthurby18@fema.gov','Male','+86-277-857-2815','visa'),
('46','Keary','Lundbech','klundbech19@topsy.com','Female','+7-790-149-5088','americanexpress'),
('47','Gert','Foro','gforo1a@t.co','Female','+86-200-556-4440','americanexpress'),
('48','Gerladina','Drover','gdrover1b@tamu.edu','Male','+591-162-488-4918','mastercard'),
('49','Randell','Butteris','rbutteris1c@admin.ch','Female','+62-445-611-6209','mastercard'),
('50','Cecilia','Wittke','cwittke1d@sourceforge.net','Male','+62-438-236-0658','americanexpress'),
('51','Auria','Kellaway','akellaway1e@chronoengine.com','Male','+30-710-672-9069','mastercard'),
('52','Mala','Tombling','mtombling1f@google.nl','Female','+372-231-810-0932','americanexpress'),
('53','Maurene','Voas','mvoas1g@nasa.gov','Female','+86-461-518-4181','visa'),
('54','Natal','Catford','ncatford1h@nydailynews.com','Female','+351-343-701-1264','visa'),
('55','Tobye','Gheorghie','tgheorghie1i@earthlink.net','Female','+1-260-592-3885','visa'),
('56','Niel','Alday','nalday1j@parallels.com','Female','+33-617-645-5386','mastercard'),
('57','Nola','Bloxsome','nbloxsome1k@pbs.org','Female','+7-417-129-8971','mastercard'),
('58','Rubia','Berrow','rberrow1l@alibaba.com','Female','+86-841-157-2644','mastercard'),
('59','Reba','Grafom','rgrafom1m@cargocollective.com','Female','+57-576-476-7677','visa'),
('60','Franklin','Gothup','fgothup1n@smh.com.au','Female','+62-156-475-2469','visa'),
('61','Erminia','Ivanishin','eivanishin1o@sciencedaily.com','Female','+351-508-287-2115','visa'),
('62','Tamarah','Eddowes','teddowes1p@blogtalkradio.com','Male','+55-157-362-9624','mastercard'),
('63','Rossy','Sappson','rsappson1q@blinklist.com','Female','+81-959-128-2732','americanexpress'),
('64','Lavina','Pringley','lpringley1r@hexun.com','Female','+86-313-409-9820','mastercard'),
('65','Gretna','Cavanaugh','gcavanaugh1s@pen.io','Male','+51-882-695-4618','americanexpress'),
('66','Giorgia','Bradtke','gbradtke1t@google.co.uk','Female','+66-843-366-3380','americanexpress'),
('67','Lonny','Walczynski','lwalczynski1u@oracle.com','Male','+351-376-347-7099','americanexpress'),
('68','Wilow','Imlock','wimlock1v@godaddy.com','Female','+351-721-165-3818','visa'),
('69','Aurora','Ennion','aennion1w@godaddy.com','Male','+46-153-647-2419','americanexpress'),
('70','Dan','Stock','dstock1x@mac.com','Female','+86-226-577-6411','mastercard'),
('71','Deedee','Spall','dspall1y@typepad.com','Male','+66-763-374-4578','mastercard'),
('72','Brandice','Dee','bdee1z@weather.com','Female','+52-950-822-1157','mastercard'),
('73','Maxim','De Beauchemp','mdebeauchemp20@furl.net','Male','+55-318-975-3689','visa'),
('74','Karil','Baversor','kbaversor21@blinklist.com','Male','+1-336-619-1271','visa'),
('75','Bunny','Mardell','bmardell22@hatena.ne.jp','Male','+81-797-808-0539','visa'),
('76','Lemmy','Ben','lben23@latimes.com','Female','+86-786-881-4964','americanexpress'),
('77','Charlena','Jurisch','cjurisch24@mlb.com','Female','+55-812-276-4144','mastercard'),
('78','Callean','Khomin','ckhomin25@jiathis.com','Male','+33-783-622-1920','mastercard'),
('79','Bryn','Gremane','bgremane26@icio.us','Male','+7-909-627-7814','mastercard'),
('80','Helen-elizabeth','Tinton','htinton27@earthlink.net','Female','+237-365-227-6402','mastercard'),
('81','Jamill','Saur','jsaur28@state.tx.us','Genderfluid','+505-868-377-9652','americanexpress'),
('82','Arel','Prosch','aprosch29@technorati.com','Female','+81-100-425-5394','mastercard'),
('83','Hailey','Lamplough','hlamplough2a@virginia.edu','Bigender','+86-977-826-3694','visa'),
('84','Dar','Mayler','dmayler2b@networksolutions.com','Female','+86-967-253-3082','visa'),
('85','Aida','Dowglass','adowglass2c@netlog.com','Male','+62-453-445-6808','americanexpress'),
('86','Codie','Donnett','cdonnett2d@utexas.edu','Female','+48-813-215-9096','americanexpress'),
('87','Renate','Babinski','rbabinski2e@webnode.com','Female','+7-728-121-8123','visa'),
('88','Tiffani','Blazewicz','tblazewicz2f@nifty.com','Male','+36-661-619-0320','americanexpress'),
('89','Jere','Caulwell','jcaulwell2g@liveinternet.ru','Female','+593-917-520-8223','visa'),
('90','Dyan','Lechelle','dlechelle2h@addtoany.com','Female','+86-497-775-3784','mastercard'),
('91','Obidiah','Rekes','orekes2i@twitter.com','Female','+53-144-778-9092','mastercard'),
('92','Eartha','Axby','eaxby2j@ftc.gov','Male','+66-626-377-3986','visa'),
('93','Borden','Druitt','bdruitt2k@tiny.cc','Male','+48-346-615-3314','visa'),
('94','Elmer','Brownbridge','ebrownbridge2l@nhs.uk','Female','+62-102-923-9964','americanexpress'),
('95','Rufe','Cheeseman','rcheeseman2m@constantcontact.com','Bigender','+86-521-230-5818','visa'),
('96','Land','Newe','lnewe2n@mysql.com','Agender','+86-295-758-6860','visa'),
('97','Curtice','Realy','crealy2o@behance.net','Male','+351-565-590-7545','visa'),
('98','Remington','Syres','rsyres2p@wikimedia.org','Female','+63-569-253-4807','mastercard'),
('99','Jameson','Durrans','jdurrans2q@auda.org.au','Male','+33-212-424-3983','americanexpress'),
('100','Dorolice','Sand','dsand2r@goo.ne.jp','Genderqueer','+63-191-875-3399','mastercard'),
('101','Hugibert','Christensen','hchristensen2s@dedecms.com','Female','+62-887-991-6951','visa'),
('102','Yardley','Dinesen','ydinesen2t@360.cn','Female','+970-337-674-9428','americanexpress'),
('103','Modestia','Stelle','mstelle2u@rakuten.co.jp','Female','+48-176-624-2491','americanexpress'),
('104','Leigha','Rozec','lrozec2v@liveinternet.ru','Genderfluid','+33-782-502-2064','visa'),
('105','Therese','Osman','tosman2w@ed.gov','Female','+420-508-786-8800','visa'),
('106','Nellie','Dyott','ndyott2x@reverbnation.com','Male','+30-991-391-2179','mastercard'),
('107','Salvatore','Mulkerrins','smulkerrins2y@cyberchimps.com','Female','+86-560-547-8434','mastercard'),
('108','Monroe','Samme','msamme2z@nhs.uk','Female','+33-982-556-3820','americanexpress'),
('109','Chloe','Lubman','clubman30@wufoo.com','Male','+55-279-866-0686','americanexpress'),
('110','Harriott','Rodenburgh','hrodenburgh31@stumbleupon.com','Female','+63-775-695-9834','mastercard'),
('111','Barbee','Baselio','bbaselio32@nifty.com','Male','+86-404-105-3740','americanexpress'),
('112','Sylvia','Totterdill','stotterdill33@unc.edu','Male','+7-257-282-2355','mastercard'),
('113','Robinia','Mallows','rmallows34@miitbeian.gov.cn','Polygender','+48-716-143-1665','visa'),
('114','Martie','Garter','mgarter35@wiley.com','Female','+62-947-302-0721','mastercard'),
('115','Herculie','Casine','hcasine36@wordpress.org','Male','+351-657-193-1371','mastercard'),
('116','Ginevra','Petera','gpetera37@purevolume.com','Female','+62-395-108-5732','mastercard'),
('117','Philipa','Jannex','pjannex38@usa.gov','Female','+48-507-551-3927','americanexpress'),
('118','Arleen','Shoesmith','ashoesmith39@umn.edu','Female','+7-770-334-5229','americanexpress'),
('119','Bary','Sarll','bsarll3a@4shared.com','Female','+47-982-439-2478','mastercard'),
('120','Lidia','Tremolieres','ltremolieres3b@t.co','Male','+62-574-204-9439','visa'),
('121','Alanson','Barfford','abarfford3c@cloudflare.com','Female','+63-321-432-6707','visa'),
('122','Josias','Stenet','jstenet3d@chicagotribune.com','Female','+62-184-358-9792','americanexpress'),
('123','Hussein','Flohard','hflohard3e@pagesperso-orange.fr','Male','+86-455-670-1689','visa'),
('124','Milt','Ripping','mripping3f@guardian.co.uk','Female','+62-919-546-8819','americanexpress'),
('125','Gisele','Drewet','gdrewet3g@taobao.com','Male','+46-486-831-1425','americanexpress'),
('126','Lorrayne','Kelson','lkelson3h@home.pl','Female','+1-762-293-8878','visa'),
('127','Archaimbaud','Lark','alark3i@biblegateway.com','Male','+34-944-537-9202','americanexpress'),
('128','Cyril','Guite','cguite3j@google.com','Female','+7-125-878-7117','mastercard'),
('129','Tristam','Jowers','tjowers3k@instagram.com','Polygender','+81-480-857-9968','americanexpress'),
('130','Mildrid','Witcherley','mwitcherley3l@hc360.com','Female','+389-753-204-5002','visa'),
('131','Daune','Sinton','dsinton3m@over-blog.com','Male','+63-295-592-3915','americanexpress'),
('132','Sidonia','Bankes','sbankes3n@intel.com','Female','+84-419-658-4777','visa'),
('133','Jude','Fibbings','jfibbings3o@bizjournals.com','Male','+62-872-464-2391','mastercard'),
('134','Wallache','Stivers','wstivers3p@noaa.gov','Male','+48-465-462-6792','mastercard'),
('135','Yanaton','Hilliam','yhilliam3q@symantec.com','Female','+86-819-875-1673','mastercard'),
('136','Lulu','Ormston','lormston3r@tripadvisor.com','Male','+48-608-722-0650','mastercard'),
('137','Suki','Stillwell','sstillwell3s@technorati.com','Male','+351-459-131-0986','visa'),
('138','Stanley','Shurville','sshurville3t@hatena.ne.jp','Male','+46-369-238-6136','mastercard'),
('139','Christye','Bambery','cbambery3u@gnu.org','Female','+30-619-799-8136','americanexpress'),
('140','Cheryl','Kalaher','ckalaher3v@bluehost.com','Male','+31-506-563-5422','mastercard'),
('141','Brooks','Gooderidge','bgooderidge3w@jalbum.net','Male','+30-368-984-4483','mastercard'),
('142','Margot','Swarbrigg','mswarbrigg3x@typepad.com','Male','+86-300-404-9002','mastercard'),
('143','Malynda','Braybrookes','mbraybrookes3y@yelp.com','Female','+55-961-992-2932','mastercard'),
('144','Kelsey','McRuvie','kmcruvie3z@bluehost.com','Male','+351-119-209-9266','mastercard'),
('145','Ricca','Taffley','rtaffley40@cdc.gov','Male','+27-493-316-3560','americanexpress'),
('146','Nikolai','Kilshall','nkilshall41@hatena.ne.jp','Female','+86-619-249-3458','mastercard'),
('147','Frants','Baldry','fbaldry42@youku.com','Female','+63-729-957-3208','visa'),
('148','Rosalia','Orbell','rorbell43@rambler.ru','Female','+86-730-882-2867','visa'),
('149','Ashil','Sebring','asebring44@engadget.com','Female','+86-853-424-0415','visa'),
('150','Fallon','Grimbaldeston','fgrimbaldeston45@utexas.edu','Female','+420-194-649-3678','mastercard'),
('151','Xenia','Fuzzey','xfuzzey46@ow.ly','Male','+66-883-531-5598','americanexpress'),
('152','Bartram','Nehlsen','bnehlsen47@army.mil','Female','+86-792-257-9953','mastercard'),
('153','Stoddard','Ratlee','sratlee48@twitter.com','Female','+1-770-208-3658','mastercard'),
('154','Deonne','Minnette','dminnette49@meetup.com','Female','+351-246-654-5466','visa'),
('155','Wally','Boolsen','wboolsen4a@histats.com','Female','+86-774-734-0769','visa'),
('156','Addison','Peres','aperes4b@china.com.cn','Male','+60-294-600-3622','americanexpress'),
('157','Desiri','Havis','dhavis4c@reference.com','Male','+7-872-676-0910','visa'),
('158','Korney','Abbatini','kabbatini4d@clickbank.net','Male','+62-675-558-1786','visa'),
('159','Reilly','Viste','rviste4e@aol.com','Female','+63-937-706-5112','visa'),
('160','Cathie','Gawith','cgawith4f@apple.com','Female','+46-321-219-2448','mastercard'),
('161','Gabrila','Longthorn','glongthorn4g@webnode.com','Genderqueer','+62-241-611-1487','americanexpress'),
('162','Adorne','Schulze','aschulze4h@fastcompany.com','Female','+62-327-847-2446','americanexpress'),
('163','Livy','Pesic','lpesic4i@list-manage.com','Female','+351-130-749-9997','mastercard'),
('164','Morie','Denford','mdenford4j@homestead.com','Female','+351-747-304-3709','mastercard'),
('165','Mamie','Pavolillo','mpavolillo4k@paypal.com','Male','+62-260-753-1806','mastercard'),
('166','Jessalin','Fullegar','jfullegar4l@usa.gov','Male','+30-183-591-3592','visa'),
('167','Orella','Goodered','ogoodered4m@t.co','Female','+86-432-176-7499','visa'),
('168','Melissa','O\\'Concannon','moconcannon4n@jiathis.com','Female','+86-551-752-4478','visa'),
('169','Garth','Branton','gbranton4o@amazon.com','Female','+62-222-539-6003','mastercard'),
('170','Cosmo','Cristoforo','ccristoforo4p@mapquest.com','Female','+255-865-147-6589','americanexpress'),
('171','Romola','Josefson','rjosefson4q@shop-pro.jp','Male','+57-728-692-2896','mastercard'),
('172','Jacklyn','Leisman','jleisman4r@miitbeian.gov.cn','Female','+52-758-514-1348','americanexpress'),
('173','Jacynth','Stent','jstent4s@facebook.com','Female','+62-816-222-3350','mastercard'),
('174','Jeffry','Keymar','jkeymar4t@hugedomains.com','Female','+86-247-293-6290','americanexpress'),
('175','Filberte','Stanett','fstanett4u@bandcamp.com','Male','+86-753-766-3036','visa'),
('176','Chester','Brooks','cbrooks4v@altervista.org','Female','+86-909-396-6289','visa'),
('177','Valentijn','Disman','vdisman4w@purevolume.com','Male','+1-917-358-2564','visa'),
('178','Haily','Saiens','hsaiens4x@123-reg.co.uk','Female','+86-257-784-1836','mastercard'),
('179','Isidore','Karpol','ikarpol4y@ehow.com','Polygender','+49-177-428-8312','americanexpress'),
('180','Baudoin','Padson','bpadson4z@pinterest.com','Female','+33-968-566-9505','visa'),
('181','Barny','Denisevich','bdenisevich50@dion.ne.jp','Female','+46-855-383-7559','visa'),
('182','Lance','Mence','lmence51@photobucket.com','Female','+63-555-701-0612','americanexpress'),
('183','Terrye','Caulliere','tcaulliere52@chronoengine.com','Female','+234-581-587-6412','visa'),
('184','Damaris','Eddowis','deddowis53@imgur.com','Female','+62-280-393-7877','americanexpress'),
('185','Kissee','Skellen','kskellen54@boston.com','Female','+237-650-419-8812','mastercard'),
('186','Ive','Romeril','iromeril55@de.vu','Male','+351-494-256-9667','mastercard'),
('187','Diego','Wilber','dwilber56@berkeley.edu','Male','+234-859-726-9833','americanexpress'),
('188','Elisabetta','Oliver-Paull','eoliverpaull57@bloomberg.com','Female','+234-912-266-7377','visa'),
('189','Pippy','Filyushkin','pfilyushkin58@sitemeter.com','Agender','+60-257-230-4022','visa'),
('190','Veronike','Dukes','vdukes59@wikipedia.org','Female','+51-465-365-8672','visa'),
('191','Ingram','Eadmeades','ieadmeades5a@virginia.edu','Female','+251-526-549-5906','mastercard'),
('192','Aron','Ritch','aritch5b@cbc.ca','Male','+62-686-492-5787','visa'),
('193','Eldin','Cristofvao','ecristofvao5c@utexas.edu','Female','+86-192-849-8212','visa'),
('194','Rivy','Tame','rtame5d@amazon.de','Male','+63-878-403-4760','mastercard'),
('195','Petronia','Simnel','psimnel5e@edublogs.org','Female','+86-192-149-3867','mastercard'),
('196','Kristoforo','Furley','kfurley5f@hhs.gov','Female','+374-756-179-4709','americanexpress'),
('197','Perle','Harrigan','pharrigan5g@google.fr','Female','+420-954-715-1887','visa'),
('198','Dennison','Sherbourne','dsherbourne5h@51.la','Female','+54-521-958-6473','mastercard'),
('199','Jeanine','Beldam','jbeldam5i@pbs.org','Male','+57-166-164-8728','mastercard'),
('200','Ulrikaumeko','Ivic','uivic5j@lulu.com','Female','+82-640-790-2559','mastercard'),
('201','Petunia','Lomb','plomb5k@free.fr','Male','+7-539-584-8269','visa'),
('202','Kaylyn','Mackin','kmackin5l@studiopress.com','Female','+992-880-567-1075','mastercard'),
('203','Winthrop','Baseggio','wbaseggio5m@webnode.com','Male','+52-563-456-4776','mastercard'),
('204','Van','Gotliffe','vgotliffe5n@nbcnews.com','Female','+86-590-633-1849','americanexpress'),
('205','Eberto','Wookey','ewookey5o@last.fm','Female','+86-149-531-1130','mastercard'),
('206','Wyndham','Halbeard','whalbeard5p@is.gd','Male','+62-983-128-6430','visa'),
('207','Gaven','Frentz','gfrentz5q@bigcartel.com','Male','+86-487-357-0179','americanexpress'),
('208','Claudelle','Witherspoon','cwitherspoon5r@auda.org.au','Male','+375-961-405-6291','americanexpress'),
('209','Lemmy','Santus','lsantus5s@techcrunch.com','Male','+62-173-780-8251','americanexpress'),
('210','Dina','Drife','ddrife5t@acquirethisname.com','Female','+86-179-168-7059','visa'),
('211','Webster','Gianolini','wgianolini5u@networksolutions.com','Male','+374-379-622-6795','visa'),
('212','Janka','Ciciari','jciciari5v@mit.edu','Female','+7-127-229-4822','americanexpress'),
('213','Evelyn','Praten','epraten5w@furl.net','Female','+39-688-725-5750','mastercard'),
('214','Celesta','Averill','caverill5x@stanford.edu','Male','+352-900-851-5153','visa'),
('215','Andrea','Statton','astatton5y@amazon.co.uk','Male','+63-167-418-0765','visa'),
('216','Kennedy','Carlsson','kcarlsson5z@unicef.org','Female','+967-253-775-5636','mastercard'),
('217','Carlen','Espinel','cespinel60@facebook.com','Male','+27-398-368-0574','visa'),
('218','Lisetta','Aggus','laggus61@baidu.com','Male','+86-205-963-2826','americanexpress'),
('219','Levin','Mouget','lmouget62@webs.com','Female','+86-141-416-7139','visa'),
('220','Gerti','Moller','gmoller63@storify.com','Male','+7-553-973-4635','mastercard'),
('221','Clary','Caines','ccaines64@disqus.com','Male','+970-864-982-9284','mastercard'),
('222','Matilde','Seakes','mseakes65@unicef.org','Female','+51-151-803-2408','visa'),
('223','Shelton','Sighard','ssighard66@bing.com','Female','+967-485-929-6578','visa'),
('224','Nevins','Kelle','nkelle67@miibeian.gov.cn','Female','+234-126-517-5398','visa'),
('225','Allissa','Betonia','abetonia68@wix.com','Female','+86-843-653-6996','americanexpress'),
('226','Angelita','Iglesia','aiglesia69@fastcompany.com','Female','+7-544-346-0575','mastercard'),
('227','Tabbatha','Elan','telan6a@globo.com','Male','+46-776-984-8859','visa'),
('228','Jakie','Caser','jcaser6b@ocn.ne.jp','Female','+355-522-897-4443','mastercard'),
('229','Solly','Howden','showden6c@bbc.co.uk','Male','+33-438-133-0534','mastercard'),
('230','Henderson','Kerwin','hkerwin6d@theglobeandmail.com','Female','+86-845-192-7468','mastercard'),
('231','Porter','Galliver','pgalliver6e@noaa.gov','Female','+358-937-169-7829','visa'),
('232','Dallas','Penhall','dpenhall6f@digg.com','Female','+420-603-822-3027','visa'),
('233','Trixi','Muirden','tmuirden6g@sfgate.com','Female','+62-283-821-6772','americanexpress'),
('234','Richy','Dericot','rdericot6h@hp.com','Male','+48-596-857-6665','visa'),
('235','Neddy','Giacomuzzo','ngiacomuzzo6i@mail.ru','Female','+54-198-216-8389','mastercard'),
('236','Ax','Cuerda','acuerda6j@hhs.gov','Male','+62-264-456-6137','visa'),
('237','Michael','Shearmur','mshearmur6k@fda.gov','Male','+33-561-735-7566','mastercard'),
('238','Gibbie','Menear','gmenear6l@gnu.org','Male','+7-175-745-4157','visa'),
('239','Kinnie','Haeslier','khaeslier6m@stumbleupon.com','Female','+7-839-884-2407','americanexpress'),
('240','Elizabet','Moorcraft','emoorcraft6n@archive.org','Female','+92-446-316-9348','visa'),
('241','Rodi','Smees','rsmees6o@alexa.com','Female','+351-163-815-9498','mastercard'),
('242','Jecho','Orred','jorred6p@tamu.edu','Female','+86-540-373-5069','americanexpress'),
('243','Helenka','Sercombe','hsercombe6q@nasa.gov','Male','+1-408-613-4341','americanexpress'),
('244','Marv','Renney','mrenney6r@elegantthemes.com','Female','+62-297-279-4159','americanexpress'),
('245','Desmund','Bastow','dbastow6s@goo.gl','Male','+420-173-788-7836','visa'),
('246','Georgeanne','Baskeyfield','gbaskeyfield6t@slate.com','Female','+86-553-644-8731','visa'),
('247','Bevin','Farrell','bfarrell6u@tamu.edu','Female','+92-971-119-0335','americanexpress'),
('248','Loleta','Ewer','lewer6v@ca.gov','Male','+63-914-439-1698','americanexpress'),
('249','Malva','Robins','mrobins6w@topsy.com','Female','+1-310-567-5388','americanexpress'),
('250','Silas','Shewery','sshewery6x@aboutads.info','Female','+7-295-798-2407','americanexpress'),
('251','Lynnet','Grinishin','lgrinishin6y@merriam-webster.com','Male','+224-720-244-1723','mastercard'),
('252','Samaria','Wisden','swisden6z@ask.com','Female','+359-294-241-5828','visa'),
('253','Perri','Wark','pwark70@bizjournals.com','Female','+62-304-387-7927','visa'),
('254','Shannon','Paxman','spaxman71@google.de','Male','+48-766-905-1734','mastercard'),
('255','Laurie','Kenwright','lkenwright72@feedburner.com','Polygender','+63-697-469-6222','mastercard'),
('256','Alberik','Bellows','abellows73@pcworld.com','Female','+63-199-287-6909','americanexpress'),
('257','Archaimbaud','Madill','amadill74@biblegateway.com','Female','+351-396-894-0168','americanexpress'),
('258','Jeni','Pherps','jpherps75@apple.com','Male','+63-366-311-5098','americanexpress'),
('259','Aliza','De Pietri','adepietri76@princeton.edu','Female','+92-205-608-0973','visa'),
('260','Gustie','D\\'Alesco','gdalesco77@salon.com','Male','+86-768-742-6978','americanexpress'),
('261','Dorri','Shackel','dshackel78@mlb.com','Male','+1-281-397-1478','mastercard'),
('262','Cecilius','Plews','cplews79@hatena.ne.jp','Male','+86-647-472-2293','americanexpress'),
('263','Nial','Geelan','ngeelan7a@tumblr.com','Male','+63-782-507-9041','visa'),
('264','Ermanno','Philippsohn','ephilippsohn7b@dion.ne.jp','Male','+7-388-502-1547','visa'),
('265','Jasen','While','jwhile7c@amazonaws.com','Female','+54-655-710-4940','americanexpress'),
('266','Malchy','Heasman','mheasman7d@skyrock.com','Male','+380-652-418-5664','mastercard'),
('267','Wilone','Moulton','wmoulton7e@gov.uk','Male','+352-267-229-8638','mastercard'),
('268','Pollyanna','Tethcote','ptethcote7f@stumbleupon.com','Male','+86-855-665-8544','mastercard'),
('269','Elliott','O\\'Lyhane','eolyhane7g@i2i.jp','Female','+234-936-650-3641','visa'),
('270','Ingamar','Littlejohn','ilittlejohn7h@amazonaws.com','Female','+7-290-555-3980','visa'),
('271','Raphaela','Smissen','rsmissen7i@businesswire.com','Female','+381-930-186-4231','mastercard'),
('272','Joly','Belsey','jbelsey7j@jugem.jp','Female','+86-450-172-7151','americanexpress'),
('273','Ninnette','Mowbray','nmowbray7k@businessweek.com','Male','+55-874-669-6330','visa'),
('274','Leupold','Biddlestone','lbiddlestone7l@icio.us','Polygender','+63-249-374-4686','mastercard'),
('275','Iseabal','Narramor','inarramor7m@tripod.com','Female','+351-219-219-0354','visa'),
('276','Thadeus','Escale','tescale7n@adobe.com','Male','+46-386-903-6790','americanexpress'),
('277','Linell','Yakovich','lyakovich7o@pen.io','Male','+86-920-545-2752','visa'),
('278','Willetta','Ismead','wismead7p@marketwatch.com','Male','+970-708-126-1294','americanexpress'),
('279','Bobinette','Rylstone','brylstone7q@tinyurl.com','Male','+850-354-228-1142','americanexpress'),
('280','Birch','Letten','bletten7r@drupal.org','Female','+63-827-151-7229','americanexpress'),
('281','Rheta','Poles','rpoles7s@twitpic.com','Female','+48-511-742-6065','mastercard'),
('282','Agathe','Macieiczyk','amacieiczyk7t@csmonitor.com','Male','+7-140-280-1282','mastercard'),
('283','Zelig','Bichard','zbichard7u@wix.com','Male','+48-696-566-9554','visa'),
('284','Louise','Bilam','lbilam7v@constantcontact.com','Male','+62-836-246-4822','mastercard'),
('285','Nettle','Fenlon','nfenlon7w@google.nl','Female','+86-767-485-4991','mastercard'),
('286','Yetty','Vearncomb','yvearncomb7x@blogs.com','Female','+33-532-357-5081','mastercard'),
('287','Shane','Catherine','scatherine7y@prlog.org','Male','+63-736-819-6493','americanexpress'),
('288','Lewes','Coldridge','lcoldridge7z@people.com.cn','Female','+62-245-155-6603','mastercard'),
('289','Eli','Mandifield','emandifield80@acquirethisname.com','Male','+86-523-795-9603','americanexpress'),
('290','Lonnie','Dalziell','ldalziell81@gnu.org','Female','+62-124-320-3245','mastercard'),
('291','Waverley','Crutchley','wcrutchley82@printfriendly.com','Male','+7-972-166-1532','americanexpress'),
('292','Andie','Simoneschi','asimoneschi83@prweb.com','Female','+380-268-986-4348','mastercard'),
('293','Claude','Deener','cdeener84@fotki.com','Female','+57-965-279-9541','americanexpress'),
('294','Edith','Strank','estrank85@ftc.gov','Female','+63-720-641-3998','americanexpress'),
('295','Titos','Stanlack','tstanlack86@newsvine.com','Female','+254-563-136-1392','americanexpress'),
('296','Hew','Gogerty','hgogerty87@yahoo.com','Female','+55-197-312-4763','americanexpress'),
('297','Margarethe','Paolillo','mpaolillo88@diigo.com','Male','+1-956-103-2362','mastercard'),
('298','Rowena','Heams','rheams89@businesswire.com','Male','+972-460-202-0747','americanexpress'),
('299','Ignazio','Mawditt','imawditt8a@wunderground.com','Female','+86-677-267-5248','americanexpress'),
('300','Jody','Hallward','jhallward8b@ucsd.edu','Agender','+86-926-813-8419','mastercard'),
('301','Tymothy','Mulbery','tmulbery8c@craigslist.org','Male','+234-114-124-9425','americanexpress'),
('302','Tracy','Tousey','ttousey8d@slashdot.org','Male','+225-467-103-8048','americanexpress'),
('303','Solly','Boles','sboles8e@parallels.com','Male','+7-416-742-9703','americanexpress'),
('304','Juline','Bourges','jbourges8f@china.com.cn','Female','+351-686-684-1614','visa'),
('305','Danya','Gymlett','dgymlett8g@facebook.com','Female','+48-255-384-5267','visa'),
('306','Kenon','Longthorne','klongthorne8h@hp.com','Male','+352-461-195-8535','visa'),
('307','Mollie','Perryman','mperryman8i@unesco.org','Male','+54-192-333-2783','visa'),
('308','Gill','Clemintoni','gclemintoni8j@hostgator.com','Male','+355-942-672-5363','mastercard'),
('309','Jessee','Nation','jnation8k@networkadvertising.org','Male','+86-196-437-2227','mastercard'),
('310','Maryanna','Brookson','mbrookson8l@marketwatch.com','Bigender','+1-973-324-1917','mastercard'),
('311','Margarethe','Legate','mlegate8m@xrea.com','Female','+46-754-984-9957','visa'),
('312','Em','Pawels','epawels8n@hhs.gov','Polygender','+86-566-816-2251','americanexpress'),
('313','Thornie','Breeder','tbreeder8o@naver.com','Male','+55-709-576-7153','americanexpress'),
('314','Nelia','Lay','nlay8p@businesswire.com','Female','+351-622-217-8220','visa'),
('315','Malinda','De Cruze','mdecruze8q@tinypic.com','Male','+359-194-466-0922','visa'),
('316','Davide','Peever','dpeever8r@sourceforge.net','Female','+63-991-346-8507','americanexpress'),
('317','Consalve','Beranek','cberanek8s@gov.uk','Bigender','+62-331-232-2269','visa'),
('318','Othilie','Fouracre','ofouracre8t@state.gov','Female','+62-309-813-7775','mastercard'),
('319','Dora','Normanville','dnormanville8u@examiner.com','Male','+62-579-226-9389','visa'),
('320','Moria','McKeon','mmckeon8v@microsoft.com','Male','+7-411-396-1577','mastercard'),
('321','Libby','Allum','lallum8w@virginia.edu','Male','+46-987-328-9593','visa'),
('322','Allx','Consterdine','aconsterdine8x@scientificamerican.com','Female','+33-319-849-7157','americanexpress'),
('323','Winnah','Beggio','wbeggio8y@wordpress.org','Genderfluid','+86-506-907-5680','mastercard'),
('324','Reggie','Sherburn','rsherburn8z@live.com','Female','+48-404-118-4489','americanexpress'),
('325','Maddie','Lambkin','mlambkin90@delicious.com','Male','+33-983-798-5514','americanexpress'),
('326','Ikey','Arnaldy','iarnaldy91@drupal.org','Male','+92-419-559-0820','visa'),
('327','Wilhelm','Trevna','wtrevna92@ameblo.jp','Male','+48-845-587-2816','visa'),
('328','Albrecht','Kinlock','akinlock93@webnode.com','Female','+30-404-676-8295','americanexpress'),
('329','Christiano','Trigwell','ctrigwell94@liveinternet.ru','Genderfluid','+7-611-453-1118','mastercard'),
('330','Guinevere','Fiddyment','gfiddyment95@issuu.com','Male','+351-973-879-1909','americanexpress'),
('331','Aluino','Beeho','abeeho96@canalblog.com','Agender','+46-590-864-6087','mastercard'),
('332','Danya','MacCleod','dmaccleod97@desdev.cn','Female','+86-859-643-6064','mastercard'),
('333','Colan','Brazil','cbrazil98@istockphoto.com','Male','+57-921-235-9280','visa'),
('334','Paco','Trusdale','ptrusdale99@theatlantic.com','Female','+62-101-136-2859','mastercard'),
('335','Marie-ann','Jewel','mjewel9a@apache.org','Female','+46-762-112-2282','visa'),
('336','Huntley','Colley','hcolley9b@edublogs.org','Female','+967-599-935-4130','mastercard'),
('337','Constance','McNaught','cmcnaught9c@ask.com','Female','+86-258-982-3353','mastercard'),
('338','Rafaello','Matussevich','rmatussevich9d@cnet.com','Male','+86-406-133-9884','mastercard'),
('339','Flinn','Luto','fluto9e@is.gd','Male','+351-560-939-5209','mastercard'),
('340','Zita','Conley','zconley9f@pcworld.com','Male','+381-321-506-3616','americanexpress'),
('341','Kordula','Ayllett','kayllett9g@stumbleupon.com','Male','+55-139-413-1653','americanexpress'),
('342','Harmony','Tegler','htegler9h@wufoo.com','Female','+86-233-923-4720','mastercard'),
('343','Nikaniki','Fessions','nfessions9i@opera.com','Female','+66-697-254-8748','americanexpress'),
('344','Missie','Triner','mtriner9j@nhs.uk','Female','+62-468-980-5287','americanexpress'),
('345','Perle','Crim','pcrim9k@naver.com','Female','+49-205-195-3723','visa'),
('346','Grayce','Townshend','gtownshend9l@whitehouse.gov','Female','+54-369-468-2148','mastercard'),
('347','Anatollo','Spincks','aspincks9m@pinterest.com','Female','+507-516-888-5084','mastercard'),
('348','Philis','Laister','plaister9n@friendfeed.com','Male','+55-679-531-3373','americanexpress'),
('349','Cherice','Salway','csalway9o@nps.gov','Male','+234-780-200-4804','visa'),
('350','Eal','Dufaur','edufaur9p@weibo.com','Male','+62-393-546-9866','mastercard'),
('351','Lydia','Rubinek','lrubinek9q@seattletimes.com','Female','+86-500-570-1537','mastercard'),
('352','Cynthia','Fann','cfann9r@rakuten.co.jp','Female','+86-500-851-8301','visa'),
('353','Pepe','Fochs','pfochs9s@spotify.com','Genderqueer','+505-851-593-9075','mastercard'),
('354','Charlotta','Altamirano','caltamirano9t@wordpress.org','Male','+1-503-661-1232','visa'),
('355','Noami','Manhare','nmanhare9u@skype.com','Male','+64-979-783-3286','visa'),
('356','Bunnie','Foale','bfoale9v@pbs.org','Female','+66-705-683-8583','mastercard'),
('357','Lanie','Shieldon','lshieldon9w@nps.gov','Male','+1-212-264-6825','visa'),
('358','Marlee','Klousner','mklousner9x@altervista.org','Female','+63-973-508-8058','visa'),
('359','Shena','Ledrun','sledrun9y@webs.com','Female','+62-280-615-2291','americanexpress'),
('360','Moyna','Swepstone','mswepstone9z@netscape.com','Female','+62-304-686-3684','visa'),
('361','Haily','Hudspith','hhudspitha0@diigo.com','Bigender','+380-208-943-5756','visa'),
('362','Candi','Sexten','csextena1@zimbio.com','Female','+30-449-896-4740','mastercard'),
('363','Kevyn','Plows','kplowsa2@homestead.com','Male','+34-154-873-7434','americanexpress'),
('364','Florri','Brucker','fbruckera3@sohu.com','Female','+375-502-771-2238','mastercard'),
('365','Dayle','Rameaux','drameauxa4@reddit.com','Male','+255-500-423-4777','visa'),
('366','Clarisse','Amesbury','camesburya5@businesswire.com','Male','+86-530-886-9617','americanexpress'),
('367','Thalia','Dunnan','tdunnana6@google.fr','Male','+998-870-438-4855','mastercard'),
('368','Jock','Corrin','jcorrina7@fc2.com','Male','+359-643-673-8048','mastercard'),
('369','Josefa','Gronowe','jgronowea8@blogspot.com','Female','+386-553-269-8132','americanexpress'),
('370','Star','de Banke','sdebankea9@bigcartel.com','Male','+86-319-777-0643','mastercard'),
('371','Coral','Laverock','claverockaa@craigslist.org','Male','+86-265-786-3982','visa'),
('372','Rhianna','Lile','rlileab@elpais.com','Male','+86-275-572-5754','americanexpress'),
('373','Maren','Pidgley','mpidgleyac@goodreads.com','Female','+86-760-587-1971','americanexpress'),
('374','Bertrand','Nowell','bnowellad@huffingtonpost.com','Female','+86-760-297-0293','mastercard'),
('375','Ardella','Blees','ableesae@imdb.com','Agender','+63-560-625-7157','visa'),
('376','Willyt','Siggery','wsiggeryaf@google.com','Female','+682-275-973-6948','americanexpress'),
('377','Zacharia','Katz','zkatzag@time.com','Male','+381-883-460-6635','visa'),
('378','Gavan','Trobridge','gtrobridgeah@woothemes.com','Male','+31-524-113-1198','americanexpress'),
('379','Mellisent','Tunnock','mtunnockai@upenn.edu','Male','+86-169-582-7939','mastercard'),
('380','Koren','Chelnam','kchelnamaj@npr.org','Male','+263-344-889-7554','americanexpress'),
('381','Alfy','Betteson','abettesonak@e-recht24.de','Female','+1-225-902-8359','americanexpress'),
('382','Emmye','Fishbie','efishbieal@opera.com','Male','+351-217-479-3797','americanexpress'),
('383','Carita','Sancho','csanchoam@seattletimes.com','Male','+63-243-403-1686','americanexpress'),
('384','Veda','Turley','vturleyan@google.de','Female','+62-483-654-4501','americanexpress'),
('385','Risa','Dawid','rdawidao@woothemes.com','Male','+504-212-899-9428','visa'),
('386','Tansy','Angus','tangusap@dion.ne.jp','Male','+62-280-205-8903','americanexpress'),
('387','Hagen','Batchelar','hbatchelaraq@vinaora.com','Female','+86-734-348-5844','americanexpress'),
('388','Margot','Ayshford','mayshfordar@naver.com','Genderfluid','+86-971-339-4892','visa'),
('389','Ailsun','Godsal','agodsalas@paypal.com','Male','+380-256-850-9787','mastercard'),
('390','Virgie','Sudell','vsudellat@harvard.edu','Female','+62-124-351-9590','americanexpress'),
('391','Svend','Clemensen','sclemensenau@wired.com','Genderfluid','+595-244-943-6273','mastercard'),
('392','Barris','Richards','brichardsav@uol.com.br','Female','+86-220-689-9349','americanexpress'),
('393','Alicea','Swoffer','aswofferaw@xrea.com','Male','+86-684-411-4479','americanexpress'),
('394','Abigale','Oldknow','aoldknowax@google.pl','Female','+30-346-617-8166','mastercard'),
('395','Antonetta','Biles','abilesay@miitbeian.gov.cn','Female','+52-932-215-6137','visa'),
('396','Dall','Simoncello','dsimoncelloaz@huffingtonpost.com','Male','+48-158-506-4338','mastercard'),
('397','Barry','Rikkard','brikkardb0@microsoft.com','Female','+46-785-198-7025','mastercard'),
('398','Garreth','Morkham','gmorkhamb1@usda.gov','Male','+57-997-843-6815','americanexpress'),
('399','Mikol','Ragdale','mragdaleb2@infoseek.co.jp','Non-binary','+86-410-120-5731','mastercard'),
('400','Nollie','Keller','nkellerb3@uiuc.edu','Male','+66-516-321-2660','americanexpress'),
('401','Jorry','Scardefield','jscardefieldb4@smh.com.au','Non-binary','+965-585-685-4045','visa'),
('402','Ursula','Bangle','ubangleb5@nba.com','Male','+86-798-882-9490','americanexpress'),
('403','Elaina','Korpal','ekorpalb6@arizona.edu','Male','+86-403-705-8952','mastercard'),
('404','Nikolaos','Walford','nwalfordb7@godaddy.com','Male','+20-325-481-3733','visa'),
('405','Donelle','Axup','daxupb8@google.pl','Male','+55-217-490-3204','mastercard'),
('406','Minne','Chetham','mchethamb9@nymag.com','Male','+86-313-473-1600','americanexpress'),
('407','Wayland','Brundle','wbrundleba@freewebs.com','Female','+62-977-311-4771','visa'),
('408','Flori','Brunet','fbrunetbb@mtv.com','Male','+63-314-214-2184','americanexpress'),
('409','Joni','Doylend','jdoylendbc@ucsd.edu','Female','+374-100-849-2303','visa'),
('410','Jules','Silson','jsilsonbd@ustream.tv','Female','+420-237-675-6826','americanexpress'),
('411','Nate','Henryson','nhenrysonbe@statcounter.com','Female','+850-670-871-2470','mastercard'),
('412','Sylvan','Lukock','slukockbf@github.com','Male','+60-156-780-2294','mastercard'),
('413','Velma','Wann','vwannbg@infoseek.co.jp','Female','+351-973-728-7179','visa'),
('414','Celinda','Jillitt','cjillittbh@constantcontact.com','Male','+387-602-515-9196','mastercard'),
('415','Ky','Farrier','kfarrierbi@vimeo.com','Female','+57-275-920-6218','mastercard'),
('416','Clayborn','Insull','cinsullbj@hc360.com','Bigender','+86-310-870-3009','mastercard'),
('417','Becki','Burfield','bburfieldbk@hexun.com','Female','+55-682-909-4081','mastercard'),
('418','Netty','Douglas','ndouglasbl@vistaprint.com','Female','+998-320-288-0374','americanexpress'),
('419','Minerva','Whiles','mwhilesbm@cmu.edu','Male','+86-362-660-4563','mastercard'),
('420','Jessalin','Letcher','jletcherbn@freewebs.com','Female','+86-230-837-7466','americanexpress'),
('421','Konstanze','Camerello','kcamerellobo@amazon.co.uk','Polygender','+31-480-293-2670','americanexpress'),
('422','Gaelan','Lechmere','glechmerebp@ucla.edu','Female','+420-336-610-2804','visa'),
('423','Walliw','Bullimore','wbullimorebq@bbc.co.uk','Female','+1-809-431-4479','mastercard'),
('424','Stavro','De Souza','sdesouzabr@phpbb.com','Female','+256-341-142-2843','americanexpress'),
('425','Rora','Cluney','rcluneybs@smh.com.au','Female','+27-882-573-8009','americanexpress'),
('426','Heinrik','Simak','hsimakbt@taobao.com','Male','+234-426-915-2398','mastercard'),
('427','Yorgo','Lytell','ylytellbu@netscape.com','Male','+62-644-956-7261','mastercard'),
('428','Tanny','Pernell','tpernellbv@ocn.ne.jp','Female','+62-279-348-4453','visa'),
('429','Diandra','Holtom','dholtombw@opensource.org','Female','+44-389-855-6691','americanexpress'),
('430','Rees','Clemmitt','rclemmittbx@blog.com','Female','+66-479-687-6975','americanexpress'),
('431','Francesco','Preuvost','fpreuvostby@ameblo.jp','Male','+33-881-850-0049','visa'),
('432','Olva','Collisson','ocollissonbz@typepad.com','Female','+420-432-366-5235','americanexpress'),
('433','Ingrim','Randall','irandallc0@yahoo.com','Genderqueer','+86-654-547-8688','visa'),
('434','Marcelo','De Vaan','mdevaanc1@nba.com','Genderfluid','+351-382-410-0869','mastercard'),
('435','Kesley','Powdrill','kpowdrillc2@imageshack.us','Male','+30-442-455-7238','americanexpress'),
('436','Aurelia','Heinlein','aheinleinc3@etsy.com','Bigender','+353-242-334-4589','visa'),
('437','Gilly','Eslinger','geslingerc4@themeforest.net','Male','+234-764-115-7305','mastercard'),
('438','Brion','Mathen','bmathenc5@cbslocal.com','Male','+503-183-850-4749','mastercard'),
('439','Armstrong','Fitchell','afitchellc6@mysql.com','Male','+359-339-871-6488','visa'),
('440','Walther','Swett','wswettc7@sun.com','Non-binary','+251-192-471-1852','americanexpress'),
('441','Noel','Redfern','nredfernc8@fema.gov','Genderqueer','+63-648-147-8521','mastercard'),
('442','Mercy','Rowell','mrowellc9@oracle.com','Female','+48-354-347-4225','americanexpress'),
('443','Kelsey','Muldrew','kmuldrewca@tuttocitta.it','Female','+27-653-135-5660','americanexpress'),
('444','Reba','Arnholz','rarnholzcb@nsw.gov.au','Female','+86-229-254-1303','visa'),
('445','Elinor','Handrok','ehandrokcc@mlb.com','Female','+48-863-743-1251','visa'),
('446','Otha','Schorah','oschorahcd@washingtonpost.com','Male','+62-477-705-1657','mastercard'),
('447','Ilario','Behning','ibehningce@surveymonkey.com','Male','+86-220-959-6125','visa'),
('448','Joellen','Dysert','jdysertcf@pen.io','Male','+62-769-294-5078','visa'),
('449','Amby','Westmore','awestmorecg@boston.com','Female','+1-415-990-4323','americanexpress'),
('450','Carce','Brattell','cbrattellch@t.co','Female','+52-303-353-4560','visa'),
('451','Egon','Drew-Clifton','edrewcliftonci@taobao.com','Male','+62-269-818-1197','visa'),
('452','Che','Swindle','cswindlecj@tiny.cc','Female','+63-135-200-8373','americanexpress'),
('453','Gregorio','Berns','gbernsck@fastcompany.com','Female','+86-126-685-6948','mastercard'),
('454','Sibyl','Hambleton','shambletoncl@nationalgeographic.com','Male','+7-184-448-2756','visa'),
('455','Bancroft','Lightwing','blightwingcm@ameblo.jp','Female','+62-880-318-0009','visa'),
('456','Elberta','Insall','einsallcn@live.com','Genderqueer','+46-223-992-3714','americanexpress'),
('457','Jarid','Trevenu','jtrevenuco@list-manage.com','Female','+62-481-535-8626','americanexpress'),
('458','Gabbey','Gibbeson','ggibbesoncp@163.com','Female','+54-840-536-5161','mastercard'),
('459','Haleigh','Matheson','hmathesoncq@nbcnews.com','Male','+86-401-972-9999','visa'),
('460','Ruthie','Loram','rloramcr@ucoz.ru','Female','+237-428-270-3699','mastercard'),
('461','Alley','Coolson','acoolsoncs@feedburner.com','Genderfluid','+55-132-798-3299','visa'),
('462','Myca','Wycliff','mwycliffct@feedburner.com','Male','+44-595-211-8262','visa'),
('463','Callean','William','cwilliamcu@tinypic.com','Female','+62-898-221-7940','americanexpress'),
('464','Maje','Lerigo','mlerigocv@apple.com','Agender','+46-835-280-7792','mastercard'),
('465','Jolyn','Wards','jwardscw@cyberchimps.com','Female','+976-714-210-2923','americanexpress'),
('466','Arleta','Touson','atousoncx@thetimes.co.uk','Male','+420-471-372-6476','mastercard'),
('467','Cecilia','Bourrel','cbourrelcy@aol.com','Female','+63-595-572-2192','visa'),
('468','Stanford','Bowland','sbowlandcz@dmoz.org','Female','+1-937-562-9045','mastercard'),
('469','Birdie','Deighton','bdeightond0@barnesandnoble.com','Female','+63-365-275-2366','americanexpress'),
('470','Martie','McWhan','mmcwhand1@constantcontact.com','Male','+86-581-668-4065','mastercard'),
('471','Antonius','Ingolotti','aingolottid2@tmall.com','Male','+86-986-349-1349','mastercard'),
('472','Gayel','Colquhoun','gcolquhound3@goo.ne.jp','Female','+351-165-236-2514','americanexpress'),
('473','Forbes','LaBastida','flabastidad4@jiathis.com','Female','+994-362-284-8715','mastercard'),
('474','Dyana','Kasher','dkasherd5@unicef.org','Male','+358-193-831-2654','americanexpress'),
('475','Bell','Drewe','bdrewed6@plala.or.jp','Male','+86-726-855-5488','visa'),
('476','Willow','Craigg','wcraiggd7@odnoklassniki.ru','Male','+81-904-288-5810','americanexpress'),
('477','Alric','Handrik','ahandrikd8@census.gov','Male','+374-935-783-1383','visa'),
('478','Elliott','Sauvain','esauvaind9@ifeng.com','Female','+86-496-219-1269','americanexpress'),
('479','Guglielma','Pauletto','gpaulettoda@trellian.com','Female','+61-438-725-3603','americanexpress'),
('480','Grete','Maryon','gmaryondb@goo.ne.jp','Male','+86-791-526-4521','visa'),
('481','Fan','Blackbrough','fblackbroughdc@de.vu','Female','+381-157-231-8122','americanexpress'),
('482','Willabella','Sherlaw','wsherlawdd@eepurl.com','Male','+30-399-486-4203','americanexpress'),
('483','Marlin','Charter','mcharterde@go.com','Female','+92-894-931-9511','americanexpress'),
('484','Johnny','Alcalde','jalcaldedf@quantcast.com','Female','+86-328-665-2810','visa'),
('485','Laurens','Hamber','lhamberdg@networksolutions.com','Male','+351-597-150-3333','visa'),
('486','Burtie','Dunthorn','bdunthorndh@edublogs.org','Male','+358-163-816-4745','americanexpress'),
('487','Ashlee','Koomar','akoomardi@cloudflare.com','Female','+33-972-550-0390','americanexpress'),
('488','Holly','Ferrarini','hferrarinidj@washington.edu','Male','+7-880-846-5816','visa'),
('489','Rosy','Sewter','rsewterdk@creativecommons.org','Female','+86-278-786-0873','mastercard'),
('490','Marchelle','Bendin','mbendindl@histats.com','Female','+86-481-942-4984','americanexpress'),
('491','Frannie','Simes','fsimesdm@earthlink.net','Female','+62-847-210-1496','visa'),
('492','Ina','Hullock','ihullockdn@4shared.com','Female','+33-792-541-8763','visa'),
('493','Laurena','Stepto','lsteptodo@sphinn.com','Male','+380-810-469-4434','mastercard'),
('494','Kassi','Scoggin','kscoggindp@nih.gov','Male','+62-810-954-5155','mastercard'),
('495','Royce','McPhee','rmcpheedq@vinaora.com','Female','+62-429-931-9153','mastercard'),
('496','Faith','Cassin','fcassindr@prweb.com','Male','+48-808-749-4458','americanexpress'),
('497','Maren','Melbury','mmelburyds@businessinsider.com','Female','+62-944-931-3048','visa'),
('498','Alie','Eede','aeededt@livejournal.com','Agender','+880-299-732-5614','visa'),
('499','Byrle','Shackle','bshackledu@mail.ru','Female','+1-985-786-6434','visa'),
('500','Joachim','Quincey','jquinceydv@dagondesign.com','Female','+351-225-547-6804','mastercard'),
('501','Berty','Bowditch','bbowditchdw@i2i.jp','Female','+86-279-183-9526','visa'),
('502','Timothea','Lawrenson','tlawrensondx@bbb.org','Female','+86-969-445-0472','visa'),
('503','Bearnard','Rudolph','brudolphdy@mapquest.com','Female','+7-255-804-4267','americanexpress'),
('504','Laney','Gounod','lgounoddz@usatoday.com','Female','+7-769-435-1867','americanexpress'),
('505','Tyne','Voelker','tvoelkere0@psu.edu','Male','+963-442-469-2944','mastercard'),
('506','Jenifer','De Filippis','jdefilippise1@weather.com','Female','+420-298-334-8953','visa'),
('507','Cleveland','Kershaw','ckershawe2@marketwatch.com','Male','+374-404-565-9035','americanexpress'),
('508','Mackenzie','Thandi','mthandie3@blogger.com','Female','+20-777-532-8798','mastercard'),
('509','Kain','Ryhorovich','kryhoroviche4@github.com','Female','+62-261-158-8375','americanexpress'),
('510','Chuck','Sex','csexe5@disqus.com','Female','+1-816-866-2709','visa'),
('511','Kylie','McIntee','kmcinteee6@harvard.edu','Male','+598-963-796-1742','visa'),
('512','Katha','Chazette','kchazettee7@usda.gov','Female','+370-104-220-2250','mastercard'),
('513','Evangelin','Whorlow','ewhorlowe8@photobucket.com','Male','+86-351-863-2367','americanexpress'),
('514','Ginnifer','Davidowich','gdavidowiche9@pen.io','Female','+995-473-792-3141','visa'),
('515','Winifield','Andrioli','wandrioliea@apache.org','Male','+48-537-622-0473','mastercard'),
('516','Maxy','Birrel','mbirreleb@cdbaby.com','Male','+86-728-669-9902','americanexpress'),
('517','Dominick','Hallgarth','dhallgarthec@wikia.com','Female','+33-853-564-4336','americanexpress'),
('518','Foster','Borth','fborthed@irs.gov','Female','+48-219-273-2396','mastercard'),
('519','Urson','Busfield','ubusfieldee@friendfeed.com','Female','+41-972-149-9742','mastercard'),
('520','Florie','Grunguer','fgrungueref@ibm.com','Female','+49-784-457-4199','visa'),
('521','Jessalin','Kelway','jkelwayeg@example.com','Male','+234-428-744-8570','americanexpress'),
('522','Colet','Yeats','cyeatseh@who.int','Male','+86-631-473-2492','americanexpress'),
('523','Rakel','Vise','rviseei@moonfruit.com','Male','+86-446-992-1367','mastercard'),
('524','Ray','Bursnell','rbursnellej@google.com.br','Female','+591-471-771-8220','visa'),
('525','Waneta','Ellcome','wellcomeek@twitpic.com','Female','+380-452-811-4545','americanexpress'),
('526','Letti','Suggitt','lsuggittel@huffingtonpost.com','Female','+389-544-915-7325','visa'),
('527','Devondra','Scardifeild','dscardifeildem@walmart.com','Female','+86-695-391-4832','visa'),
('528','Shannen','Yepiskopov','syepiskopoven@nytimes.com','Male','+1-514-937-4988','visa'),
('529','Christyna','Arndtsen','carndtseneo@dmoz.org','Female','+48-522-345-6298','visa'),
('530','Dean','Howson','dhowsonep@de.vu','Male','+51-829-335-3332','mastercard'),
('531','Keven','Ringrose','kringroseeq@hugedomains.com','Male','+267-207-322-0521','mastercard'),
('532','Vincents','Scollard','vscollarder@ameblo.jp','Male','+48-975-743-1203','americanexpress'),
('533','Janey','Matysik','jmatysikes@newsvine.com','Male','+63-884-805-4151','visa'),
('534','Gianina','Simmgen','gsimmgenet@opensource.org','Male','+92-601-752-8261','mastercard'),
('535','Lorianna','Parramore','lparramoreeu@yelp.com','Genderfluid','+93-432-670-3718','visa'),
('536','Vincenz','Edmunds','vedmundsev@wsj.com','Male','+269-349-643-7650','mastercard'),
('537','Gonzalo','Poplee','gpopleeew@mozilla.com','Female','+81-933-255-8346','americanexpress'),
('538','Anitra','Meaddowcroft','ameaddowcroftex@desdev.cn','Female','+63-959-224-6863','mastercard'),
('539','Christel','St Louis','cstlouisey@liveinternet.ru','Male','+1-135-199-2905','americanexpress'),
('540','Elnora','Counter','ecounterez@nsw.gov.au','Male','+55-758-473-8262','americanexpress'),
('541','Laurence','Jaquiss','ljaquissf0@forbes.com','Female','+7-529-364-7780','mastercard'),
('542','Nicoli','Gutcher','ngutcherf1@trellian.com','Male','+251-343-610-3539','visa'),
('543','Harley','Gilks','hgilksf2@example.com','Male','+255-957-435-4528','mastercard'),
('544','Demetris','Spens','dspensf3@redcross.org','Non-binary','+30-186-749-8316','visa'),
('545','Xena','Pordall','xpordallf4@virginia.edu','Female','+86-222-137-9538','americanexpress'),
('546','Melisa','Rosten','mrostenf5@artisteer.com','Female','+86-799-860-4723','americanexpress'),
('547','Marj','Santora','msantoraf6@prweb.com','Female','+62-712-952-7221','americanexpress'),
('548','Natty','Pynner','npynnerf7@themeforest.net','Female','+352-662-507-3020','visa'),
('549','June','Micklewright','jmicklewrightf8@bloomberg.com','Male','+94-234-528-8504','americanexpress'),
('550','Odelinda','Gerok','ogerokf9@nih.gov','Female','+62-131-486-4404','mastercard'),
('551','Clarita','Hammer','chammerfa@apple.com','Female','+353-150-207-8026','mastercard'),
('552','Vanna','Lytle','vlytlefb@ucla.edu','Male','+7-923-666-2439','mastercard'),
('553','Nester','Bosma','nbosmafc@irs.gov','Male','+31-345-119-0438','mastercard'),
('554','Vyky','Altham','valthamfd@cyberchimps.com','Male','+7-225-281-7892','visa'),
('555','Fernande','McQuorkel','fmcquorkelfe@ca.gov','Female','+380-659-775-4649','americanexpress'),
('556','Silva','Dougher','sdougherff@sbwire.com','Male','+420-468-747-8311','mastercard'),
('557','Wildon','Haughey','whaugheyfg@com.com','Genderqueer','+48-133-794-4256','mastercard'),
('558','Dyann','Noads','dnoadsfh@rakuten.co.jp','Female','+48-709-926-9220','mastercard'),
('559','Sarajane','Wringe','swringefi@bing.com','Female','+46-710-514-8405','mastercard'),
('560','Welsh','Borborough','wborboroughfj@netscape.com','Female','+420-697-207-8830','mastercard'),
('561','Raimondo','Leggate','rleggatefk@prweb.com','Male','+86-470-751-2737','visa'),
('562','Maribel','Eburah','meburahfl@theguardian.com','Male','+57-148-471-6140','visa'),
('563','Faustine','Degoy','fdegoyfm@live.com','Female','+51-597-283-9565','americanexpress'),
('564','Zorine','Treen','ztreenfn@github.io','Female','+234-827-567-9382','americanexpress'),
('565','Olav','Sapauton','osapautonfo@bluehost.com','Polygender','+51-566-564-1742','mastercard'),
('566','Berkie','Waddy','bwaddyfp@diigo.com','Female','+967-568-537-5565','americanexpress'),
('567','Case','Farre','cfarrefq@bizjournals.com','Female','+49-912-612-8573','mastercard'),
('568','Madeline','Woodruff','mwoodrufffr@icq.com','Female','+963-971-940-4871','americanexpress'),
('569','Eirena','Renault','erenaultfs@intel.com','Bigender','+86-750-385-2392','visa'),
('570','Gilly','Bertie','gbertieft@umn.edu','Male','+267-932-535-2081','mastercard'),
('571','Loleta','Reck','lreckfu@bigcartel.com','Female','+93-788-257-3752','visa'),
('572','Deeanne','Dibb','ddibbfv@nydailynews.com','Male','+420-884-944-5515','visa'),
('573','Roselia','Corrett','rcorrettfw@ebay.com','Male','+62-304-749-4160','visa'),
('574','Dougy','Kilfeather','dkilfeatherfx@huffingtonpost.com','Male','+86-712-274-4166','americanexpress'),
('575','Ev','Reeves','ereevesfy@woothemes.com','Male','+86-176-146-8152','mastercard'),
('576','Doralyn','Darcy','ddarcyfz@indiegogo.com','Male','+7-844-261-9447','americanexpress'),
('577','Xavier','Sheals','xshealsg0@google.ru','Male','+86-868-578-0699','americanexpress'),
('578','Engelbert','Noli','enolig1@acquirethisname.com','Female','+33-752-496-5760','americanexpress'),
('579','Colet','Fountaine','cfountaineg2@dedecms.com','Female','+371-783-676-2514','mastercard'),
('580','Henriette','Andreolli','handreollig3@diigo.com','Female','+387-151-686-3506','visa'),
('581','Delcine','Castagneri','dcastagnerig4@ucsd.edu','Male','+1-590-458-8675','americanexpress'),
('582','Mathilda','Ashall','mashallg5@alexa.com','Female','+86-748-508-2936','mastercard'),
('583','Sim','Cossum','scossumg6@artisteer.com','Female','+46-211-575-1669','americanexpress'),
('584','Wendie','Josey','wjoseyg7@lulu.com','Female','+57-474-407-7253','visa'),
('585','Hernando','Pauler','hpaulerg8@wufoo.com','Male','+358-686-407-9590','americanexpress'),
('586','Quintilla','Mewitt','qmewittg9@unc.edu','Female','+57-741-714-3997','visa'),
('587','Pincas','Parham','pparhamga@github.com','Female','+55-452-369-9232','americanexpress'),
('588','Barbie','Tiplady','btipladygb@eventbrite.com','Female','+62-946-108-5683','americanexpress'),
('589','Constantine','Klimt','cklimtgc@un.org','Female','+351-179-606-8341','mastercard'),
('590','Chrysa','Rawdales','crawdalesgd@qq.com','Male','+62-603-679-7422','americanexpress'),
('591','Marylinda','Woolfenden','mwoolfendenge@nsw.gov.au','Female','+62-364-199-0526','mastercard'),
('592','Edgar','Archbold','earchboldgf@va.gov','Male','+94-462-135-2307','mastercard'),
('593','Goddart','Wykes','gwykesgg@so-net.ne.jp','Female','+81-691-163-7396','americanexpress'),
('594','Keri','Manser','kmansergh@domainmarket.com','Female','+48-504-103-2570','visa'),
('595','Mannie','Nelane','mnelanegi@alibaba.com','Female','+86-446-786-6410','mastercard'),
('596','Rosaleen','Rossoni','rrossonigj@patch.com','Female','+86-130-711-9979','visa'),
('597','Consolata','Pittoli','cpittoligk@disqus.com','Female','+57-646-581-5217','mastercard'),
('598','Hamlen','McGregor','hmcgregorgl@e-recht24.de','Male','+86-831-277-7643','mastercard'),
('599','Kiley','Rosser','krossergm@unesco.org','Female','+358-238-490-8766','americanexpress'),
('600','Jada','Ryland','jrylandgn@networkadvertising.org','Male','+62-557-568-5783','americanexpress'),
('601','Arabel','Ketcher','aketchergo@ameblo.jp','Genderqueer','+48-453-883-8862','americanexpress'),
('602','Lucian','De Pero','ldeperogp@histats.com','Male','+86-354-201-6004','visa'),
('603','Niles','Eddolls','neddollsgq@4shared.com','Male','+7-958-369-6075','americanexpress'),
('604','Kanya','Lomax','klomaxgr@soup.io','Non-binary','+62-367-385-8518','mastercard'),
('605','Lelia','Pigot','lpigotgs@ebay.co.uk','Male','+380-118-858-3243','mastercard'),
('606','Skipp','Fugere','sfugeregt@liveinternet.ru','Male','+86-119-508-7143','visa'),
('607','Kristian','d\\' Elboux','kdelbouxgu@irs.gov','Female','+63-147-742-6972','mastercard'),
('608','Augie','Bleier','ableiergv@yahoo.co.jp','Female','+372-819-751-9022','mastercard'),
('609','Jillie','O\\'Fallon','jofallongw@vinaora.com','Female','+63-789-575-7550','mastercard'),
('610','Janifer','Maskelyne','jmaskelynegx@bandcamp.com','Female','+27-970-212-4624','americanexpress'),
('611','Pat','Readings','preadingsgy@gizmodo.com','Female','+27-490-907-0212','visa'),
('612','Letitia','Spere','lsperegz@t-online.de','Male','+420-110-812-8213','americanexpress'),
('613','Lauraine','Isakov','lisakovh0@imageshack.us','Female','+57-439-224-7572','mastercard'),
('614','Chen','Haken','chakenh1@google.pl','Female','+86-399-700-4679','americanexpress'),
('615','Jordain','Thame','jthameh2@symantec.com','Female','+48-997-681-8135','visa'),
('616','Elnar','Hacquel','ehacquelh3@clickbank.net','Male','+86-724-546-5173','mastercard'),
('617','Marjorie','Epine','mepineh4@canalblog.com','Genderfluid','+267-475-736-5059','visa'),
('618','Tanya','Faulkner','tfaulknerh5@dell.com','Female','+51-493-147-6503','americanexpress'),
('619','Cesar','Friary','cfriaryh6@reuters.com','Female','+63-307-684-3454','visa'),
('620','Emili','Ogborne','eogborneh7@weather.com','Female','+7-662-990-4919','mastercard'),
('621','Garek','Rossey','grosseyh8@symantec.com','Male','+86-973-168-1619','visa'),
('622','Germaine','Antham','ganthamh9@ed.gov','Male','+55-206-157-0118','visa'),
('623','Orsola','Kearsley','okearsleyha@vinaora.com','Female','+1-763-936-2231','mastercard'),
('624','Carola','Guitte','cguittehb@howstuffworks.com','Male','+33-647-808-6583','mastercard'),
('625','Sheff','Karpets','skarpetshc@mapy.cz','Female','+1-406-264-8911','visa'),
('626','Phebe','Wesley','pwesleyhd@noaa.gov','Female','+48-958-963-9867','americanexpress'),
('627','Jayson','Latchford','jlatchfordhe@digg.com','Male','+970-852-576-8329','mastercard'),
('628','Rolf','Vasilmanov','rvasilmanovhf@aol.com','Male','+86-570-816-8957','americanexpress'),
('629','Sarena','Hatherell','shatherellhg@blog.com','Female','+86-619-856-8220','mastercard'),
('630','Jojo','Behr','jbehrhh@bigcartel.com','Male','+33-955-161-2209','americanexpress'),
('631','Idette','Bras','ibrashi@rakuten.co.jp','Male','+63-595-891-5135','mastercard'),
('632','Jasmin','Dowdam','jdowdamhj@cyberchimps.com','Female','+62-268-311-7694','americanexpress'),
('633','Mercy','Mitcham','mmitchamhk@yellowbook.com','Male','+51-876-181-0687','americanexpress'),
('634','Roxanna','Gascoyen','rgascoyenhl@blogtalkradio.com','Male','+251-464-324-0975','americanexpress'),
('635','Leyla','Hrinchishin','lhrinchishinhm@reverbnation.com','Male','+86-925-450-5502','mastercard'),
('636','Tarra','Lindenstrauss','tlindenstrausshn@tumblr.com','Male','+7-338-202-5565','visa'),
('637','Skyler','MacTrustrie','smactrustrieho@china.com.cn','Male','+234-627-780-7506','mastercard'),
('638','Gratiana','Quinn','gquinnhp@nyu.edu','Male','+387-137-492-5342','mastercard'),
('639','Liz','Sheara','lshearahq@google.com.au','Female','+86-225-621-1526','visa'),
('640','Terza','Koppelmann','tkoppelmannhr@google.es','Male','+62-574-886-3522','americanexpress'),
('641','Constancy','Lawford','clawfordhs@icio.us','Male','+62-788-316-4928','mastercard'),
('642','Adelina','Jollands','ajollandsht@geocities.com','Female','+86-937-560-3681','visa'),
('643','Orbadiah','Vanyukhin','ovanyukhinhu@columbia.edu','Male','+30-532-353-4215','americanexpress'),
('644','Kayley','Turmell','kturmellhv@webnode.com','Male','+7-884-960-1093','visa'),
('645','Chev','Kasbye','ckasbyehw@vkontakte.ru','Male','+51-365-316-9580','visa'),
('646','Emery','Dilston','edilstonhx@elpais.com','Female','+52-780-915-4066','mastercard'),
('647','Leroi','Chave','lchavehy@eepurl.com','Male','+420-441-515-0519','americanexpress'),
('648','Morna','Roset','mrosethz@friendfeed.com','Female','+62-428-407-2332','visa'),
('649','Ewell','Wyper','ewyperi0@nationalgeographic.com','Female','+62-885-870-4622','americanexpress'),
('650','Fayette','Byng','fbyngi1@google.de','Agender','+351-980-239-1926','americanexpress'),
('651','Winfred','Chretien','wchretieni2@msn.com','Female','+420-843-982-7583','mastercard'),
('652','Gaultiero','Michin','gmichini3@ibm.com','Female','+504-860-433-1421','americanexpress'),
('653','Skye','MacMichael','smacmichaeli4@cornell.edu','Female','+354-717-479-4432','mastercard'),
('654','Lonnie','Hitter','lhitteri5@bloglovin.com','Male','+502-560-637-1073','visa'),
('655','Paulina','Dilger','pdilgeri6@behance.net','Male','+86-372-810-0171','americanexpress'),
('656','Ned','Pattison','npattisoni7@lulu.com','Female','+55-806-449-7504','mastercard'),
('657','Alvera','Rebanks','arebanksi8@samsung.com','Male','+86-858-800-4032','americanexpress'),
('658','Mile','Perceval','mpercevali9@cnet.com','Genderqueer','+970-505-756-0883','visa'),
('659','Patience','Boundy','pboundyia@shinystat.com','Female','+964-664-233-5030','visa'),
('660','Robenia','Lind','rlindib@zimbio.com','Male','+63-320-878-2961','americanexpress'),
('661','Magda','Whittlesea','mwhittleseaic@japanpost.jp','Female','+351-613-404-1105','visa'),
('662','Merry','Kynan','mkynanid@lycos.com','Female','+86-458-533-0830','americanexpress'),
('663','Brocky','Borleace','bborleaceie@woothemes.com','Male','+351-746-126-5479','mastercard'),
('664','Marty','Rivenzon','mrivenzonif@redcross.org','Male','+221-275-525-0005','mastercard'),
('665','Hoebart','Strattan','hstrattanig@nifty.com','Male','+63-244-719-4947','americanexpress'),
('666','Nonie','Settle','nsettleih@de.vu','Female','+66-341-720-9646','visa'),
('667','Dale','Baniard','dbaniardii@tripadvisor.com','Female','+62-310-629-7873','americanexpress'),
('668','Jourdain','Avraam','javraamij@google.nl','Non-binary','+63-497-377-0517','mastercard'),
('669','Codi','Chitson','cchitsonik@vkontakte.ru','Male','+86-169-252-1557','americanexpress'),
('670','Phillis','Scriver','pscriveril@ning.com','Male','+7-488-738-8625','mastercard'),
('671','Janeen','Battista','jbattistaim@pinterest.com','Male','+420-994-547-8020','mastercard'),
('672','Herman','Uvedale','huvedalein@pbs.org','Male','+52-573-520-2194','mastercard'),
('673','Cynthy','Behagg','cbehaggio@cafepress.com','Female','+86-329-556-8735','americanexpress'),
('674','Beniamino','Schouthede','bschouthedeip@baidu.com','Male','+82-934-454-6600','visa'),
('675','Wilbert','Arrington','warringtoniq@unicef.org','Female','+62-813-131-9275','mastercard'),
('676','Joye','Coombes','jcoombesir@cmu.edu','Male','+385-931-458-9613','mastercard'),
('677','Garey','Hallett','ghallettis@mit.edu','Female','+55-937-129-0990','mastercard'),
('678','Yvon','Beeson','ybeesonit@sciencedaily.com','Male','+351-785-787-9500','mastercard'),
('679','Norry','Goreway','ngorewayiu@oracle.com','Female','+260-795-739-0121','mastercard'),
('680','Joni','Paolillo','jpaolilloiv@slideshare.net','Male','+371-778-348-4668','mastercard'),
('681','Wood','Dugmore','wdugmoreiw@china.com.cn','Female','+62-598-329-0265','americanexpress'),
('682','Britte','Kidsley','bkidsleyix@engadget.com','Female','+420-542-891-5024','visa'),
('683','Daven','Davids','ddavidsiy@ebay.co.uk','Male','+62-353-293-3637','americanexpress'),
('684','Wally','Calafato','wcalafatoiz@mysql.com','Female','+420-135-987-8423','visa'),
('685','Salem','Dutnall','sdutnallj0@thetimes.co.uk','Male','+254-762-103-7239','visa'),
('686','Meyer','Caulcutt','mcaulcuttj1@g.co','Female','+62-617-524-7996','mastercard'),
('687','Aviva','Whilde','awhildej2@nps.gov','Male','+81-827-697-2318','mastercard'),
('688','Raffarty','Meanwell','rmeanwellj3@state.gov','Male','+46-676-429-1016','mastercard'),
('689','Bink','Eusden','beusdenj4@howstuffworks.com','Male','+63-740-583-8362','mastercard'),
('690','Aeriell','Feathersby','afeathersbyj5@moonfruit.com','Male','+964-447-420-3025','mastercard'),
('691','Cristie','Honniebal','chonniebalj6@topsy.com','Female','+880-893-463-0280','visa'),
('692','Dorene','Landsbury','dlandsburyj7@aol.com','Male','+1-419-594-4744','visa'),
('693','Leontyne','Darbey','ldarbeyj8@yolasite.com','Male','+54-609-644-0029','mastercard'),
('694','Renaud','Sutherel','rsutherelj9@npr.org','Male','+351-785-619-5803','mastercard'),
('695','Neron','Hodcroft','nhodcroftja@squidoo.com','Female','+7-568-106-2329','americanexpress'),
('696','Madge','Becker','mbeckerjb@salon.com','Female','+7-656-355-8128','mastercard'),
('697','Chickie','Ransome','cransomejc@noaa.gov','Male','+234-980-659-8312','visa'),
('698','Stephen','Braden','sbradenjd@tinypic.com','Female','+351-522-664-9318','visa'),
('699','Tymothy','O\\'Lennane','tolennaneje@rakuten.co.jp','Male','+7-538-658-5481','americanexpress'),
('700','Ag','Chetwind','achetwindjf@e-recht24.de','Male','+234-851-339-2235','visa'),
('701','Rennie','Hemphall','rhemphalljg@bluehost.com','Female','+54-401-975-1122','mastercard'),
('702','Kimberlyn','Bendon','kbendonjh@storify.com','Female','+299-359-175-1363','visa'),
('703','Delilah','Wasmuth','dwasmuthji@princeton.edu','Female','+380-890-560-7774','mastercard'),
('704','Nathalie','Crufts','ncruftsjj@myspace.com','Female','+963-716-417-3174','mastercard'),
('705','Chrissie','Smoughton','csmoughtonjk@newyorker.com','Male','+977-951-996-2463','americanexpress'),
('706','Shay','Pennock','spennockjl@howstuffworks.com','Male','+7-919-242-8216','americanexpress'),
('707','Yves','Devote','ydevotejm@google.ca','Male','+33-678-513-1726','mastercard'),
('708','Wilhelm','Tenant','wtenantjn@hexun.com','Male','+46-370-749-5026','mastercard'),
('709','Patrizio','Blazy','pblazyjo@webeden.co.uk','Female','+1-573-782-0597','mastercard'),
('710','Kenny','Sandeman','ksandemanjp@ucla.edu','Male','+62-795-384-8771','americanexpress'),
('711','Locke','Jedrychowski','ljedrychowskijq@uol.com.br','Female','+7-389-941-4679','visa'),
('712','Delmer','McKiddin','dmckiddinjr@icq.com','Female','+86-669-617-4432','visa'),
('713','Giffie','Gozzett','ggozzettjs@discovery.com','Female','+86-582-559-5145','americanexpress'),
('714','Kristoforo','Owtram','kowtramjt@vkontakte.ru','Female','+420-240-501-6817','mastercard'),
('715','Kenon','Wilmington','kwilmingtonju@unicef.org','Male','+86-297-870-3884','visa'),
('716','Rubin','Pulbrook','rpulbrookjv@feedburner.com','Male','+86-726-687-7933','mastercard'),
('717','Eilis','McGriele','emcgrielejw@github.com','Male','+86-699-549-6121','mastercard'),
('718','Matty','Ellson','mellsonjx@yelp.com','Genderqueer','+86-717-500-4669','mastercard'),
('719','Mozelle','Jozwicki','mjozwickijy@w3.org','Male','+63-303-684-4159','mastercard'),
('720','Randell','O\\'Quin','roquinjz@edublogs.org','Male','+509-358-208-8854','americanexpress'),
('721','Milzie','Clayton','mclaytonk0@salon.com','Male','+351-896-273-3495','americanexpress'),
('722','Johny','Winfred','jwinfredk1@fastcompany.com','Bigender','+62-687-540-0188','mastercard'),
('723','Cayla','Winspear','cwinspeark2@go.com','Female','+351-398-908-9900','mastercard'),
('724','Frazer','Byfield','fbyfieldk3@marketwatch.com','Polygender','+86-836-909-0221','mastercard'),
('725','Stillmann','Shrieve','sshrievek4@usda.gov','Male','+55-818-293-3076','visa'),
('726','Kara','Measor','kmeasork5@soup.io','Non-binary','+46-454-720-0978','mastercard'),
('727','Jo-anne','Tompkins','jtompkinsk6@howstuffworks.com','Female','+62-923-148-5118','americanexpress'),
('728','Minnie','Prendiville','mprendivillek7@theglobeandmail.com','Male','+33-940-372-5114','visa'),
('729','Alan','Richter','arichterk8@smh.com.au','Male','+62-145-960-6493','mastercard'),
('730','Dotty','Trosdall','dtrosdallk9@independent.co.uk','Female','+86-333-761-8966','mastercard'),
('731','Avis','Sinnie','asinnieka@wunderground.com','Male','+98-209-450-6197','visa'),
('732','Gaylor','Garrow','ggarrowkb@statcounter.com','Bigender','+55-543-285-9510','americanexpress'),
('733','Gail','Luten','glutenkc@php.net','Male','+1-949-291-0133','mastercard'),
('734','Betteann','Widdowson','bwiddowsonkd@fc2.com','Genderfluid','+62-101-153-8555','mastercard'),
('735','Carl','Toulch','ctoulchke@ycombinator.com','Female','+63-970-337-8646','mastercard'),
('736','Yetty','Bownass','ybownasskf@mtv.com','Male','+63-659-392-9096','mastercard'),
('737','Salem','Carmen','scarmenkg@dyndns.org','Female','+46-615-220-2366','americanexpress'),
('738','Cristabel','Western','cwesternkh@imageshack.us','Female','+86-868-339-1480','visa'),
('739','Adela','McGrouther','amcgroutherki@springer.com','Female','+850-150-484-6859','visa'),
('740','Nora','Varney','nvarneykj@marketwatch.com','Male','+62-813-788-0237','visa'),
('741','Halsey','Clerk','hclerkkk@histats.com','Male','+39-626-283-9872','visa'),
('742','Shelagh','Coupman','scoupmankl@is.gd','Female','+976-261-985-8385','americanexpress'),
('743','Phineas','Matyasik','pmatyasikkm@vinaora.com','Female','+81-634-297-6063','americanexpress'),
('744','Brandy','McCarry','bmccarrykn@vk.com','Male','+7-129-563-1371','mastercard'),
('745','Isidoro','Strudwick','istrudwickko@a8.net','Male','+66-716-229-1316','visa'),
('746','Colman','Marieton','cmarietonkp@exblog.jp','Male','+86-749-722-0058','americanexpress'),
('747','Kacey','Kirdsch','kkirdschkq@trellian.com','Female','+1-907-491-8427','mastercard'),
('748','Gilli','Yushmanov','gyushmanovkr@w3.org','Male','+62-239-215-5521','visa'),
('749','Janis','Nineham','jninehamks@reference.com','Male','+1-904-829-3574','mastercard'),
('750','Lester','Nicolson','lnicolsonkt@constantcontact.com','Female','+968-998-801-9017','visa'),
('751','Cristi','Shaw','cshawku@pbs.org','Female','+63-387-836-5972','visa'),
('752','Anitra','Reddie','areddiekv@github.io','Male','+7-146-370-9503','visa'),
('753','Thayne','Koba','tkobakw@typepad.com','Female','+63-274-283-2591','americanexpress'),
('754','Thorsten','Papworth','tpapworthkx@google.ru','Female','+86-747-178-0453','americanexpress'),
('755','Libbie','Powderham','lpowderhamky@ehow.com','Female','+84-713-364-6973','visa'),
('756','Debbie','Skitterel','dskitterelkz@prweb.com','Female','+47-642-471-2354','mastercard'),
('757','Kiele','Tiplady','ktipladyl0@skyrock.com','Female','+55-811-221-0836','mastercard'),
('758','Bobbe','Cleall','bclealll1@freewebs.com','Male','+55-281-870-7514','americanexpress'),
('759','Oates','Ollin','oollinl2@w3.org','Polygender','+86-294-602-7788','mastercard'),
('760','Margarethe','Edmeades','medmeadesl3@feedburner.com','Female','+7-746-672-0243','visa'),
('761','Yvor','Merryweather','ymerryweatherl4@berkeley.edu','Female','+62-502-608-0415','mastercard'),
('762','Constantine','Tesoe','ctesoel5@weather.com','Male','+420-742-652-2965','mastercard'),
('763','Rachel','Cardno','rcardnol6@acquirethisname.com','Female','+63-183-174-0114','mastercard'),
('764','Kirsten','Lackney','klackneyl7@gnu.org','Female','+62-646-502-7031','americanexpress'),
('765','Wesley','Cashin','wcashinl8@themeforest.net','Male','+855-302-654-6572','mastercard'),
('766','Tailor','Spybey','tspybeyl9@thetimes.co.uk','Male','+86-231-989-7462','americanexpress'),
('767','Lanae','Bottrill','lbottrillla@phoca.cz','Female','+998-689-229-7421','americanexpress'),
('768','Ezequiel','Barz','ebarzlb@deliciousdays.com','Male','+7-595-891-9778','americanexpress'),
('769','Gerty','MacFarlan','gmacfarlanlc@ftc.gov','Polygender','+94-722-472-9110','americanexpress'),
('770','Hazlett','Dingsdale','hdingsdaleld@stanford.edu','Polygender','+54-727-981-2020','mastercard'),
('771','Simonette','Dennant','sdennantle@cnet.com','Female','+298-261-709-8651','americanexpress'),
('772','Lionel','Sperski','lsperskilf@latimes.com','Male','+386-697-230-0761','americanexpress'),
('773','Benn','Atkyns','batkynslg@i2i.jp','Male','+86-626-735-2657','visa'),
('774','Evelin','Linfitt','elinfittlh@mtv.com','Genderfluid','+1-779-471-3663','visa'),
('775','Cassie','Patshull','cpatshullli@latimes.com','Female','+351-289-231-8654','mastercard'),
('776','Alvera','Moyers','amoyerslj@drupal.org','Female','+62-532-405-7248','mastercard'),
('777','Riobard','Gouley','rgouleylk@globo.com','Male','+63-743-589-9913','americanexpress'),
('778','Mady','Graber','mgraberll@walmart.com','Female','+62-206-912-0196','visa'),
('779','Ynez','Allnutt','yallnuttlm@ucoz.ru','Female','+420-707-507-6912','americanexpress'),
('780','Lesli','Goncalo','lgoncaloln@msn.com','Male','+7-851-592-5895','visa'),
('781','Arielle','Flanders','aflanderslo@shinystat.com','Female','+86-930-464-4550','mastercard'),
('782','Nonah','Beceril','nbecerillp@privacy.gov.au','Male','+84-634-684-9987','mastercard'),
('783','Manon','Miebes','mmiebeslq@blogs.com','Female','+48-973-450-0898','mastercard'),
('784','Patsy','Aggis','paggislr@utexas.edu','Female','+54-698-226-0499','americanexpress'),
('785','Letti','Ambrozewicz','lambrozewiczls@qq.com','Male','+62-757-746-5658','visa'),
('786','Idalina','Tinmouth','itinmouthlt@xrea.com','Female','+55-805-973-1443','visa'),
('787','Robbie','Alf','ralflu@printfriendly.com','Bigender','+255-320-979-6436','americanexpress'),
('788','Sibley','Fenkel','sfenkellv@devhub.com','Female','+52-344-944-0979','visa'),
('789','Shannah','Knottley','sknottleylw@sakura.ne.jp','Female','+48-949-845-9888','americanexpress'),
('790','Cal','Lebell','clebelllx@google.de','Female','+55-243-331-2007','visa'),
('791','Yorgos','Jedrzejewicz','yjedrzejewiczly@craigslist.org','Female','+212-482-434-1582','visa'),
('792','Olwen','Terbrugge','oterbruggelz@netvibes.com','Female','+49-367-127-1043','americanexpress'),
('793','Cynde','Fasler','cfaslerm0@seesaa.net','Female','+218-694-705-1728','mastercard'),
('794','Carey','McMurdo','cmcmurdom1@a8.net','Polygender','+86-764-242-8088','americanexpress'),
('795','Codi','Tomczak','ctomczakm2@mlb.com','Male','+63-132-473-2984','americanexpress'),
('796','Hewie','Goodspeed','hgoodspeedm3@blogspot.com','Female','+7-652-906-9088','americanexpress'),
('797','Magdalene','McCobb','mmccobbm4@hostgator.com','Female','+43-239-253-8034','americanexpress'),
('798','Wat','Ten Broek','wtenbroekm5@squarespace.com','Female','+86-868-287-9057','americanexpress'),
('799','Benedikta','Roft','broftm6@house.gov','Male','+48-246-287-9581','americanexpress'),
('800','Bamby','Buttle','bbuttlem7@linkedin.com','Female','+63-256-741-7912','mastercard'),
('801','Andrey','York','ayorkm8@imageshack.us','Male','+55-460-630-4431','visa'),
('802','Jenny','Keningley','jkeningleym9@example.com','Female','+86-579-229-7641','americanexpress'),
('803','Wallache','Regelous','wregelousma@dmoz.org','Female','+86-267-231-8653','visa'),
('804','Elayne','Dowles','edowlesmb@un.org','Female','+595-324-131-3557','americanexpress'),
('805','Jarrett','Durrett','jdurrettmc@bravesites.com','Female','+57-167-488-3934','mastercard'),
('806','Gordy','Cardnell','gcardnellmd@scientificamerican.com','Male','+48-198-368-7471','americanexpress'),
('807','Nealy','Ughelli','nughellime@huffingtonpost.com','Male','+7-774-971-2566','mastercard'),
('808','Alon','MacTrustam','amactrustammf@army.mil','Female','+62-116-220-6686','americanexpress'),
('809','Minnnie','Dabbes','mdabbesmg@flickr.com','Female','+81-752-298-6067','americanexpress'),
('810','Chloris','Harriot','charriotmh@phpbb.com','Female','+81-499-878-9129','visa'),
('811','Rebeka','Bechley','rbechleymi@mapy.cz','Male','+62-836-511-8540','mastercard'),
('812','Olvan','Screaton','oscreatonmj@mapy.cz','Female','+62-983-171-8561','visa'),
('813','Ole','Boxall','oboxallmk@xrea.com','Female','+62-454-227-8403','mastercard'),
('814','Ferris','Saunderson','fsaundersonml@spiegel.de','Female','+62-823-614-2536','americanexpress'),
('815','Misti','Clardge','mclardgemm@epa.gov','Male','+86-222-237-2668','mastercard'),
('816','Danielle','Cortin','dcortinmn@123-reg.co.uk','Female','+380-135-576-0898','visa'),
('817','Ward','Sygrove','wsygrovemo@cocolog-nifty.com','Male','+86-664-104-3411','mastercard'),
('818','Mellisa','Hazzard','mhazzardmp@ycombinator.com','Genderfluid','+62-360-460-6639','visa'),
('819','Red','Androlli','randrollimq@examiner.com','Male','+20-518-522-6428','visa'),
('820','Tomaso','Giordano','tgiordanomr@yahoo.com','Female','+502-720-666-5617','americanexpress'),
('821','Elfie','Morant','emorantms@huffingtonpost.com','Female','+86-970-630-9813','visa'),
('822','Mellisa','Margach','mmargachmt@google.co.jp','Male','+850-685-912-1326','americanexpress'),
('823','Noellyn','McAdam','nmcadammu@va.gov','Male','+84-821-460-5642','americanexpress'),
('824','Anita','Heball','aheballmv@harvard.edu','Male','+62-500-183-1085','americanexpress'),
('825','Megan','Pockey','mpockeymw@disqus.com','Female','+1-619-943-3626','visa'),
('826','Edik','Wymer','ewymermx@bluehost.com','Genderfluid','+63-817-990-8425','visa'),
('827','Farr','Slavin','fslavinmy@storify.com','Female','+86-750-145-2829','visa'),
('828','Jami','Goldsmith','jgoldsmithmz@tiny.cc','Non-binary','+62-560-794-3929','mastercard'),
('829','Barnard','Dabel','bdabeln0@g.co','Female','+86-781-314-8444','mastercard'),
('830','Dill','Benck','dbenckn1@howstuffworks.com','Female','+86-660-718-7925','americanexpress'),
('831','Zachery','Shorland','zshorlandn2@google.ca','Male','+48-734-931-4202','visa'),
('832','Alika','Haydn','ahaydnn3@ask.com','Female','+380-668-269-5409','visa'),
('833','Tuckie','Titford','ttitfordn4@is.gd','Male','+54-449-376-1435','mastercard'),
('834','Tatiania','Milksop','tmilksopn5@usa.gov','Non-binary','+98-220-395-0810','visa'),
('835','Brina','Scadden','bscaddenn6@ted.com','Male','+381-267-898-7832','mastercard'),
('836','Kort','Tubb','ktubbn7@youtu.be','Female','+86-578-238-7861','americanexpress'),
('837','Reginald','Edgerly','redgerlyn8@csmonitor.com','Male','+62-174-479-8248','visa'),
('838','Sayre','Kedward','skedwardn9@etsy.com','Bigender','+33-646-511-3750','visa'),
('839','Wyn','Balharry','wbalharryna@omniture.com','Polygender','+62-994-653-2475','visa'),
('840','Annaliese','Laurent','alaurentnb@a8.net','Male','+62-674-171-2021','visa'),
('841','Charlton','Vasilchenko','cvasilchenkonc@cargocollective.com','Female','+56-184-955-6206','mastercard'),
('842','Sheilakathryn','Klementz','sklementznd@baidu.com','Genderqueer','+233-748-541-0255','americanexpress'),
('843','Perle','Glen','pglenne@livejournal.com','Male','+62-728-414-1845','mastercard'),
('844','Pamela','Laite','plaitenf@latimes.com','Female','+1-405-252-4360','mastercard'),
('845','Barbara','Harborow','bharborowng@webs.com','Male','+82-316-450-3679','americanexpress'),
('846','Theodoric','Cohn','tcohnnh@skype.com','Female','+1-775-442-9923','americanexpress'),
('847','Ivory','Brosi','ibrosini@github.io','Male','+52-438-390-1922','visa'),
('848','Aubrey','De la Yglesias','adelayglesiasnj@slideshare.net','Female','+86-771-831-0745','mastercard'),
('849','Alvera','Hidderley','ahidderleynk@narod.ru','Male','+81-221-205-3266','visa'),
('850','Lisabeth','Golsworthy','lgolsworthynl@domainmarket.com','Male','+62-461-443-0918','americanexpress'),
('851','Sheena','MacDonogh','smacdonoghnm@sun.com','Male','+1-708-247-1447','visa'),
('852','Zorine','Roger','zrogernn@weibo.com','Female','+86-559-509-1557','mastercard'),
('853','Currie','Aizic','caizicno@sbwire.com','Non-binary','+86-310-898-3396','americanexpress'),
('854','Nikolaos','Koop','nkoopnp@ameblo.jp','Female','+62-246-405-2868','mastercard'),
('855','Maynard','Fellnee','mfellneenq@unc.edu','Female','+86-395-916-2259','mastercard'),
('856','Merwyn','Croad','mcroadnr@wp.com','Male','+352-636-878-3923','visa'),
('857','Deny','Heeks','dheeksns@dmoz.org','Male','+1-301-244-2483','americanexpress'),
('858','Caterina','Touret','ctouretnt@sohu.com','Female','+81-655-503-8647','americanexpress'),
('859','Catriona','Ladbury','cladburynu@tiny.cc','Male','+33-901-955-5126','visa'),
('860','Heindrick','Fitzsymons','hfitzsymonsnv@hibu.com','Male','+81-972-499-0331','mastercard'),
('861','Johann','Giacobazzi','jgiacobazzinw@slashdot.org','Male','+234-776-112-4628','visa'),
('862','Virgilio','Kirgan','vkirgannx@jimdo.com','Non-binary','+359-117-949-5344','americanexpress'),
('863','Silvio','Hover','shoverny@princeton.edu','Male','+86-478-277-1514','mastercard'),
('864','Bibby','Scriviner','bscrivinernz@google.com.au','Male','+381-209-849-0433','visa'),
('865','Ranice','Murkin','rmurkino0@shinystat.com','Male','+46-590-344-6245','americanexpress'),
('866','Sara-ann','Dogg','sdoggo1@vimeo.com','Female','+54-206-426-9590','mastercard'),
('867','Denver','MacFarland','dmacfarlando2@mapy.cz','Female','+970-949-144-4054','visa'),
('868','Katlin','Wakely','kwakelyo3@t-online.de','Male','+39-243-763-6155','americanexpress'),
('869','Manolo','Cannon','mcannono4@boston.com','Female','+62-457-348-3594','visa'),
('870','Tammi','Hover','thovero5@auda.org.au','Female','+380-447-875-8033','mastercard'),
('871','Normand','De Carolis','ndecaroliso6@webs.com','Male','+229-753-620-8056','visa'),
('872','Kipp','Izzett','kizzetto7@hubpages.com','Non-binary','+220-845-786-9937','americanexpress'),
('873','Homere','De la Perrelle','hdelaperrelleo8@bloglovin.com','Female','+86-732-179-2317','americanexpress'),
('874','Welsh','McParland','wmcparlando9@dell.com','Male','+86-399-875-3584','mastercard'),
('875','Henryetta','Kynvin','hkynvinoa@wufoo.com','Male','+380-652-722-1427','visa'),
('876','Billie','Wallach','bwallachob@dyndns.org','Female','+670-165-325-6009','americanexpress'),
('877','Riley','Grimsditch','rgrimsditchoc@acquirethisname.com','Female','+380-120-134-7884','visa'),
('878','Sonnie','Elacoate','selacoateod@washington.edu','Female','+263-779-249-4054','americanexpress'),
('879','Abbe','Cordes','acordesoe@yelp.com','Male','+51-437-179-1291','americanexpress'),
('880','Ernie','Leads','eleadsof@army.mil','Female','+7-333-235-7735','visa'),
('881','Heall','Killiner','hkillinerog@sbwire.com','Male','+967-926-771-6477','mastercard'),
('882','Meaghan','Burghill','mburghilloh@bbc.co.uk','Male','+7-329-968-1219','visa'),
('883','Rainer','Crosser','rcrosseroi@vk.com','Female','+52-582-258-4669','mastercard'),
('884','Morna','Harberer','mharbereroj@pcworld.com','Male','+63-893-791-7645','visa'),
('885','Dorette','Bartelot','dbartelotok@is.gd','Male','+420-352-369-8231','visa'),
('886','Fredrick','Edmands','fedmandsol@spotify.com','Bigender','+62-733-655-1779','visa'),
('887','Dolph','Humber','dhumberom@yandex.ru','Female','+1-669-746-1757','visa'),
('888','Amory','Labbey','alabbeyon@google.ru','Female','+252-548-821-1043','visa'),
('889','Regan','Hubbuck','rhubbuckoo@ed.gov','Agender','+48-297-940-5150','visa'),
('890','Farrand','Tenwick','ftenwickop@xing.com','Genderfluid','+351-972-269-8920','visa'),
('891','Jessi','Rentoll','jrentolloq@youku.com','Female','+62-977-651-1388','americanexpress'),
('892','Matthiew','Glancy','mglancyor@ibm.com','Agender','+963-305-689-0497','mastercard'),
('893','Nicolis','Vigar','nvigaros@plala.or.jp','Female','+7-282-660-2544','americanexpress'),
('894','Tamarra','L\\'Hommeau','tlhommeauot@paypal.com','Male','+62-473-268-1643','mastercard'),
('895','Selig','Stair','sstairou@free.fr','Male','+81-506-860-2219','americanexpress'),
('896','Rosabel','Garbert','rgarbertov@unesco.org','Female','+351-968-650-9474','americanexpress'),
('897','Karylin','Klemmt','kklemmtow@chron.com','Male','+963-145-867-6723','mastercard'),
('898','Catrina','Rides','cridesox@bravesites.com','Female','+992-454-419-8653','americanexpress'),
('899','Constancia','Massenhove','cmassenhoveoy@springer.com','Agender','+7-751-469-8919','visa'),
('900','Anson','Stickland','asticklandoz@comsenz.com','Male','+62-143-473-2628','visa'),
('901','Leshia','Redborn','lredbornp0@noaa.gov','Male','+86-782-600-8664','americanexpress'),
('902','Ricki','Deackes','rdeackesp1@latimes.com','Male','+351-574-454-7299','americanexpress'),
('903','Mina','McPhelim','mmcphelimp2@prnewswire.com','Female','+62-699-388-7635','visa'),
('904','Cyb','Wrotham','cwrothamp3@gnu.org','Male','+63-950-938-6555','americanexpress'),
('905','Bronny','Waller','bwallerp4@house.gov','Female','+351-674-186-4632','mastercard'),
('906','Leonore','Pimmocke','lpimmockep5@deviantart.com','Male','+20-960-419-4845','visa'),
('907','Blondie','Truscott','btruscottp6@amazon.co.uk','Male','+55-402-175-5211','visa'),
('908','Annadiane','Kuzma','akuzmap7@irs.gov','Male','+86-936-331-8781','mastercard'),
('909','Alford','Lighten','alightenp8@sitemeter.com','Male','+86-630-481-5255','visa'),
('910','Eugenius','Karpushkin','ekarpushkinp9@auda.org.au','Male','+46-695-583-2497','visa'),
('911','Pepillo','Graser','pgraserpa@squidoo.com','Male','+86-861-210-7929','mastercard'),
('912','Peterus','Bycraft','pbycraftpb@artisteer.com','Female','+62-110-722-9370','visa'),
('913','Zabrina','Gilman','zgilmanpc@google.com.au','Male','+359-162-833-3983','mastercard'),
('914','Ginni','Kroll','gkrollpd@thetimes.co.uk','Female','+86-799-655-9215','visa'),
('915','Neel','Bremmer','nbremmerpe@ucoz.ru','Female','+86-263-736-3583','mastercard'),
('916','Berty','Atkirk','batkirkpf@spotify.com','Male','+234-912-157-6332','visa'),
('917','Gerrard','Sperwell','gsperwellpg@umn.edu','Male','+55-738-223-9296','mastercard'),
('918','Merilyn','Tuckey','mtuckeyph@homestead.com','Male','+62-594-873-4820','mastercard'),
('919','Jarrad','Capstick','jcapstickpi@bloglovin.com','Female','+507-803-291-2609','visa'),
('920','Gerome','Lufkin','glufkinpj@clickbank.net','Female','+30-153-996-5670','visa'),
('921','Verine','Drillingcourt','vdrillingcourtpk@cam.ac.uk','Male','+62-790-910-3057','americanexpress'),
('922','Selle','Learie','sleariepl@cpanel.net','Male','+86-330-119-9878','visa'),
('923','Georgeanna','Howlin','ghowlinpm@chron.com','Female','+62-755-290-0372','visa'),
('924','Gui','Jeeves','gjeevespn@dropbox.com','Male','+48-971-221-6466','visa'),
('925','Alwyn','Blyden','ablydenpo@nasa.gov','Male','+48-438-558-6327','americanexpress'),
('926','Paten','Bennallck','pbennallckpp@pcworld.com','Female','+33-356-914-1878','americanexpress'),
('927','Fredrika','Zute','fzutepq@narod.ru','Male','+62-225-640-8469','americanexpress'),
('928','Lissie','Stavers','lstaverspr@go.com','Male','+380-619-807-0741','mastercard'),
('929','Gunar','Cranmer','gcranmerps@etsy.com','Male','+7-275-437-4575','visa'),
('930','Thurstan','Payn','tpaynpt@bloglovin.com','Female','+254-901-820-1789','mastercard'),
('931','Nanci','Towe','ntowepu@ed.gov','Female','+7-102-780-2873','visa'),
('932','Idette','Bankes','ibankespv@ihg.com','Genderqueer','+46-627-934-9459','visa'),
('933','Theressa','Paddingdon','tpaddingdonpw@pbs.org','Male','+7-335-720-0457','visa'),
('934','Gan','Boynes','gboynespx@addtoany.com','Female','+420-454-565-6466','mastercard'),
('935','Nara','Gibbonson','ngibbonsonpy@npr.org','Male','+63-829-431-5193','visa'),
('936','Darlleen','O\\'Carran','docarranpz@berkeley.edu','Male','+55-410-671-3363','americanexpress'),
('937','Arnold','Humphries','ahumphriesq0@netscape.com','Male','+46-306-610-4587','americanexpress'),
('938','Sileas','Berka','sberkaq1@hc360.com','Male','+36-616-288-3409','americanexpress'),
('939','Stesha','Banker','sbankerq2@diigo.com','Female','+86-801-530-1604','mastercard'),
('940','Alex','Bathowe','abathoweq3@google.es','Male','+351-330-871-9263','visa'),
('941','Annalise','Juschka','ajuschkaq4@businessinsider.com','Female','+57-873-669-6592','americanexpress'),
('942','Alano','Albinson','aalbinsonq5@google.co.uk','Male','+7-163-980-3752','americanexpress'),
('943','Dannel','Winchester','dwinchesterq6@bandcamp.com','Female','+1-256-102-9917','visa'),
('944','Cord','Lewington','clewingtonq7@cisco.com','Female','+351-985-894-4133','americanexpress'),
('945','Hedwig','Lotte','hlotteq8@lulu.com','Male','+30-828-955-2129','visa'),
('946','Kevyn','Rickaby','krickabyq9@miibeian.gov.cn','Genderqueer','+55-242-422-5152','visa'),
('947','Aldon','Greim','agreimqa@facebook.com','Female','+359-605-193-7274','americanexpress'),
('948','Lina','Cruddace','lcruddaceqb@geocities.com','Female','+48-289-622-8965','visa'),
('949','Vin','Suthworth','vsuthworthqc@state.tx.us','Female','+62-774-399-0102','americanexpress'),
('950','Moyra','Bakewell','mbakewellqd@howstuffworks.com','Female','+7-281-974-7890','visa'),
('951','Pepillo','Molloy','pmolloyqe@ameblo.jp','Male','+47-285-418-2453','visa'),
('952','Joell','Lawrenz','jlawrenzqf@netlog.com','Male','+63-542-194-0766','visa'),
('953','Sarita','Scurr','sscurrqg@reference.com','Bigender','+51-102-281-8743','visa'),
('954','Trumaine','Gerler','tgerlerqh@technorati.com','Male','+268-200-153-0833','americanexpress'),
('955','Bobine','Beekmann','bbeekmannqi@shutterfly.com','Female','+216-150-937-0606','visa'),
('956','Elisabet','Benger','ebengerqj@weather.com','Male','+27-692-926-2315','visa'),
('957','Junina','Tewelson','jtewelsonqk@yahoo.com','Female','+359-276-797-9548','mastercard'),
('958','Vale','Feldharker','vfeldharkerql@about.com','Male','+374-800-385-3574','visa'),
('959','Lexine','Reglar','lreglarqm@slashdot.org','Female','+359-695-240-5863','americanexpress'),
('960','Jacqueline','Pietroni','jpietroniqn@qq.com','Female','+351-873-472-5781','americanexpress'),
('961','Bamby','Absalom','babsalomqo@istockphoto.com','Male','+502-380-363-2032','americanexpress'),
('962','Ana','McPhail','amcphailqp@plala.or.jp','Female','+86-828-117-3152','americanexpress'),
('963','Man','Pratton','mprattonqq@columbia.edu','Male','+212-606-892-1294','americanexpress'),
('964','Madonna','Aharoni','maharoniqr@tmall.com','Female','+967-287-678-4192','visa'),
('965','Adrian','VanBrugh','avanbrughqs@tmall.com','Male','+420-853-363-0658','mastercard'),
('966','Ragnar','Gooderham','rgooderhamqt@cnn.com','Male','+385-808-891-4163','mastercard'),
('967','Constantia','Garr','cgarrqu@seattletimes.com','Female','+86-322-669-9772','americanexpress'),
('968','Elbertine','Tivers','etiversqv@topsy.com','Female','+351-362-725-5643','visa'),
('969','Corby','Dunsire','cdunsireqw@w3.org','Male','+81-183-598-4599','mastercard'),
('970','Clarita','Crotty','ccrottyqx@amazon.de','Genderqueer','+27-763-286-3552','mastercard'),
('971','Percy','Holleran','pholleranqy@dedecms.com','Female','+86-269-291-3926','visa'),
('972','Oren','Crummie','ocrummieqz@msu.edu','Genderqueer','+7-555-786-4071','americanexpress'),
('973','Lindsey','Plastow','lplastowr0@yolasite.com','Female','+62-141-256-7026','visa'),
('974','Barbi','Lenz','blenzr1@biblegateway.com','Bigender','+51-526-130-8622','visa'),
('975','Noll','Barringer','nbarringerr2@jigsy.com','Female','+33-428-173-6361','visa'),
('976','Shantee','Matteini','smatteinir3@scribd.com','Male','+380-394-126-0214','visa'),
('977','Dela','Tice','dticer4@columbia.edu','Female','+55-103-956-0887','visa'),
('978','Verne','Fricke','vfricker5@paginegialle.it','Female','+62-925-800-4775','visa'),
('979','Lyndsie','Erskine Sandys','lerskinesandysr6@bing.com','Bigender','+351-411-474-3334','visa'),
('980','Ric','Race','rracer7@goo.gl','Male','+353-367-332-4750','mastercard'),
('981','Heda','Berth','hberthr8@unicef.org','Female','+58-123-557-1457','visa'),
('982','Kelly','Ridler','kridlerr9@hp.com','Female','+86-246-874-3903','mastercard'),
('983','Axel','Bridge','abridgera@wix.com','Female','+235-856-572-4977','mastercard'),
('984','Melvin','Krauss','mkraussrb@skype.com','Male','+62-409-385-9787','americanexpress'),
('985','Teddy','Mc Grath','tmcgrathrc@gizmodo.com','Male','+506-498-761-4703','americanexpress'),
('986','Goldia','Cowpertwait','gcowpertwaitrd@typepad.com','Male','+62-671-181-4607','visa'),
('987','Taddeusz','Fuzzard','tfuzzardre@naver.com','Bigender','+54-396-929-5267','americanexpress'),
('988','Roz','MacGruer','rmacgruerrf@aboutads.info','Female','+86-122-133-8508','mastercard'),
('989','Merell','Broose','mbrooserg@yahoo.com','Female','+503-631-141-7151','visa'),
('990','Casey','Brewin','cbrewinrh@xrea.com','Female','+1-195-120-4839','americanexpress'),
('991','Kandace','Pristnor','kpristnorri@vk.com','Female','+86-174-411-7832','visa'),
('992','Lorin','Freestone','lfreestonerj@europa.eu','Female','+86-354-998-6930','americanexpress'),
('993','Quillan','Macbane','qmacbanerk@yandex.ru','Female','+380-877-156-5743','mastercard'),
('994','Kerianne','Sydes','ksydesrl@squidoo.com','Male','+7-237-265-7775','americanexpress'),
('995','Ulises','Headley','uheadleyrm@go.com','Female','+55-523-843-8604','americanexpress'),
('996','Ardene','Broadway','abroadwayrn@exblog.jp','Female','+81-793-332-3778','americanexpress'),
('997','Hayyim','Beaufoy','hbeaufoyro@lulu.com','Male','+1-210-227-5657','mastercard'),
('998','Anton','MacNess','amacnessrp@google.nl','Male','+234-972-451-7013','americanexpress'),
('999','Eugenia','Fairholme','efairholmerq@example.com','Female','+63-786-810-4380','visa'),
('1000','Jammal','Druhan','jdruhanrr@uol.com.br','Female','+994-737-865-7916','visa')''',
    '''CREATE TABLE IF NOT EXISTS fraudulent_txn
(
event_time string,
acc_id string,
transaction_id string,
f_name string,
l_name string,
email string,
gender string,
phone string,
card string,
lat double,
lon double,
amount bigint,
PRIMARY KEY (event_time, acc_id)
)
PARTITION BY HASH PARTITIONS 16
STORED AS KUDU
TBLPROPERTIES ('kudu.num_tablet_replicas' = '1')'''
]

SSB_CREATE_TABLES_STMT = '''
DROP TABLE IF EXISTS fraudulent_txn;
CREATE TABLE fraudulent_txn (
  `event_time` VARCHAR(2147483647),
  `diff_ms` BIGINT,
  `account_id` VARCHAR(2147483647),
  `txn1_id` VARCHAR(2147483647),
  `txn2_id` VARCHAR(2147483647),
  `amount` INT,
  `lat` DOUBLE,
  `lon` DOUBLE,
  `lat1` DOUBLE,
  `lon1` DOUBLE,
  `distance` DECIMAL(32, 16),
  `f_name` VARCHAR(2147483647),
  `l_name` VARCHAR(2147483647),
  `email` VARCHAR(2147483647),
  `card` VARCHAR(2147483647),
  `gender` VARCHAR(2147483647),
  `phone` VARCHAR(2147483647)
) WITH (
  'connector' = 'kafka: edge2ai-kafka',
  'format' = 'json',
  'scan.startup.mode' = 'latest-offset',
  'topic' = 'fraudulent_txn'
)
;

DROP TABLE IF EXISTS transactions;
CREATE TABLE transactions (
  `ts` BIGINT,
  `account_id` VARCHAR(2147483647),
  `transaction_id` VARCHAR(2147483647),
  `amount` INT,
  `lat` DOUBLE,
  `lon` DOUBLE,
  `fraud_score` DOUBLE,
  `model_response` ROW<`fraud_score` DOUBLE>,
  `event_time` AS CAST(from_unixtime(floor(`ts`/1000)) AS TIMESTAMP(3)),
  WATERMARK FOR `event_time` AS `event_time` - INTERVAL '3' SECOND
) WITH (
  'connector' = 'kafka: edge2ai-kafka',
  'scan.transform.js.code' = 'var parsed = JSON.parse(record.value); parsed.ts = new java.text.SimpleDateFormat(''yyyy-MM-dd HH:mm:ss'').parse(parsed.ts).getTime(); JSON.stringify(parsed);',
  'format' = 'json',
  'topic' = 'transactions',
  'scan.startup.mode' = 'latest-offset'
)
;
'''

SSB_DROP_TABLES_STMT = '''
DROP TABLE IF EXISTS fraudulent_txn;
DROP TABLE IF EXISTS transactions;
'''

UDF_HAVETOKM_CODE = '''function HAVETOKM(lat1,lon1,lat2,lon2) {
  function toRad(x) {
    return x * Math.PI / 180;
  }

  var R = 6371; // km
  var x1 = lat2 - lat1;
  var dLat = toRad(x1);
  var x2 = lon2 - lon1;
  var dLon = toRad(x2)
  var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  var d = R * c;

  // convert to string
  return d;
}
HAVETOKM($p0, $p1, $p2, $p3);  // this line must exist
'''

UDF_TO_KUDU_STRING_CODE = '''function TO_KUDU_STRING(input){
   return input;
}
TO_KUDU_STRING($p0);  // this line must exist
'''

SSB_FRAUD_JOB = '''DROP TEMPORARY VIEW IF EXISTS frauds;
CREATE TEMPORARY VIEW frauds AS
SELECT
  cast(txn1.event_time as string) as event_time,
  txn2.ts - txn1.ts as diff_ms,
  txn1.account_id,
  txn1.transaction_id as txn1_id,
  txn2.transaction_id as txn2_id,
  txn2.amount,
  txn2.lat,
  txn2.lon,
  txn1.lat as lat1,
  txn1.lon as lon1,
  HAVETOKM(txn1.lat, txn1.lon, txn2.lat, txn2.lon) as distance,
  c.f_name, c.l_name, c.email, c.card, c.gender, c.phone
FROM transactions as txn1
JOIN transactions as txn2
  ON txn1.account_id = txn2.account_id
JOIN `edge2ai-kudu`.`default_database`.`default.customers` as c
  ON c.acc_id = txn1.account_id
WHERE txn1.transaction_id <> txn2.transaction_id
  AND txn2.event_time BETWEEN txn1.event_time AND txn1.event_time + INTERVAL '10' MINUTE
  AND HAVETOKM(txn1.lat, txn1.lon, txn2.lat, txn2.lon) > 1
;

INSERT INTO fraudulent_txn
SELECT *
FROM frauds
;

INSERT INTO `edge2ai-kudu`.`default_database`.`default.fraudulent_txn` (event_time, acc_id, transaction_id, f_name, l_name, email, gender, phone, card, lat, lon, amount)
SELECT
  to_kudu_string(event_time),
  to_kudu_string(account_id),
  to_kudu_string(txn2_id),
  to_kudu_string(f_name),
  to_kudu_string(l_name),
  to_kudu_string(email),
  to_kudu_string(gender),
  to_kudu_string(phone),
  to_kudu_string(card),
  lat,
  lon,
  amount
FROM frauds
;
'''

DATAVIZ_CONNECTION_TYPE = 'impyla'
DATAVIZ_CONNECTION_NAME = 'Impala'
DATAVIZ_CONNECTION_PARAMS = {
    'HOST': get_hostname(),
    'PORT': '21050',
    'MODE': 'binary',
    'AUTH': 'plain' if is_kerberos_enabled() else 'nosasl',
    'SOCK': 'ssl' if is_tls_enabled() else 'normal',
}

DATAVIZ_EXPORT_FILE = 'fraud-demo-viz.json'

def read_in_schema(uri=_TRANSACTION_SCHEMA_URI):
    if 'TRANSACTION_SCHEMA_FILE' in os.environ and os.path.exists(os.environ['TRANSACTION_SCHEMA_FILE']):
        return open(os.environ['TRANSACTION_SCHEMA_FILE']).read()
    else:
        r = requests.get(uri)
        if r.status_code == 200:
            return r.text
        raise ValueError("Unable to retrieve schema from URI, response was %s", r.status_code)


class FraudWorkshop(AbstractWorkshop):

    @classmethod
    def workshop_id(cls):
        """Return a short string to identify the workshop."""
        return 'fraud'

    @classmethod
    def prereqs(cls):
        """
        Return a list of prereqs for this workshop. The list can contain either:
          - Strings identifying the name of other workshops that need to be setup before this one does. In
            this case all the labs of the specified workshop will be setup.
          - Tuples (String, Integer), where the String specifies the name of the workshop and Integer the number
            of the last lab of that workshop to be executed/setup.
        """
        return []

    @classmethod
    def is_runnable(cls):
        """
        Return True is the workshop is runnable (i.e. all the necessary prerequisites are satisfied).
        This method can be overriden to check for necessary prerequisites.
        """
        return cdsw.is_cdsw_installed() and ssb.is_ssb_installed() and ssb.is_csa16_or_later()

    def before_setup(self):
        self.context.root_pg = nf.set_environment()
        if is_kerberos_enabled():
            ssb.upload_keytab('admin', '/keytabs/admin.keytab')

    def after_setup(self):
        #nf.wait_for_data(PG_NAME)
        pass

    def teardown(self):
        root_pg = nf.set_environment()

        dataviz.delete_dataset(dc_name=DATAVIZ_CONNECTION_NAME)
        dataviz.delete_connection(dc_name=DATAVIZ_CONNECTION_NAME)

        canvas.schedule_process_group(root_pg.id, False)
        while True:
            failed = False
            for controller in canvas.list_all_controllers(root_pg.id):
                try:
                    canvas.schedule_controller(controller, False)
                    LOG.debug('Controller %s stopped.', controller.component.name)
                except ApiException as exc:
                    if exc.status == 409 and 'is referenced by' in exc.body:
                        LOG.debug('Controller %s failed to stop. Will retry later.', controller.component.name)
                        failed = True
            if not failed:
                break

        ssb.stop_all_jobs(wait_secs=3)
        ssb.execute_sql(SSB_DROP_TABLES_STMT, job_name="drop_tables")
        ssb.delete_all_jobs()
        ssb.delete_all_udfs()
        ssb.delete_all_data_providers()
        nf.delete_all(root_pg)
        schreg.delete_all_schemas()
        reg_client = versioning.get_registry_client('NiFi Registry')
        if reg_client:
            versioning.delete_registry_client(reg_client)
        nifireg.delete_flows(REGISTRY_BUCKET_NAME)
        kudu.drop_table()
        cdsw.delete_all_model_api_keys()

    def lab1_register_schema(self):
        schreg.create_schema('transactions', 'Transaction data', read_in_schema())

    def lab2_create_topics(self):
        for topic in TOPICS:
            smm.create_topic(topic, 10)

    def lab3_create_kudu_tables(self):
        for stmt in CREATE_TABLES_STMTS:
            impala.execute_sql(stmt)

    def lab4_nifi_flow(self):
        # Create a bucket in NiFi Registry
        self.context.fraud_bucket = versioning.get_registry_bucket(REGISTRY_BUCKET_NAME)
        if not self.context.fraud_bucket:
            self.context.fraud_bucket = versioning.create_registry_bucket(REGISTRY_BUCKET_NAME)

        # Create a NiFi Registry client
        self.context.reg_client = versioning.create_registry_client(
            'NiFi Registry', nifireg.get_url(), 'The registry...')

        # Create NiFi Process Group
        self.context.fraud_pg = canvas.create_process_group(self.context.root_pg, PG_NAME, (330, 350))
        self.context.fraud_flow = nifireg.save_flow_ver(
            self.context.fraud_pg, self.context.reg_client, self.context.fraud_bucket,
            flow_name='FraudDetectionPG',
            comment='Enabled version control - {}'.format(self.run_id))

        if is_tls_enabled():
            if is_kerberos_enabled():
                security_protocol = 'SASL_SSL'
                sasl_mechanism = 'PLAIN'
            else:
                security_protocol = 'SSL'
                sasl_mechanism = 'GSSAPI'
        else:
            if is_kerberos_enabled():
                security_protocol = 'SASL_PLAINTEXT'
                sasl_mechanism = 'PLAIN'
            else:
                security_protocol = 'PLAINTEXT'
                sasl_mechanism = 'GSSAPI'
        params = [
            parameters.prepare_parameter('fraud_topic', 'fraud_suspects'),
            parameters.prepare_parameter('input.host', '${hostname()}'),
            parameters.prepare_parameter('input.port', '6900'),
            parameters.prepare_parameter('kafka.brokers', kafka.get_bootstrap_servers()),
            parameters.prepare_parameter('kafka.sasl.mechanism', sasl_mechanism),
            parameters.prepare_parameter('kafka.security.protocol', security_protocol),
            parameters.prepare_parameter('kudu.master', kudu.get_masters()),
            parameters.prepare_parameter('model.endpoint.url', 'http://${hostname()}:5000/model'),
            parameters.prepare_parameter('schema.name', 'transactions'),
            parameters.prepare_parameter('schema.registry.url', schreg.get_api_url()),
            parameters.prepare_parameter('transaction_table', 'default.transactions'),
            parameters.prepare_parameter('transaction_topic', 'transactions'),
            parameters.prepare_parameter('workload.password', get_the_pwd(), sensitive=True),
            parameters.prepare_parameter('workload.user', 'admin'),
        ]

        self.context.params = parameters.create_parameter_context('fraud-params', 'fraud-params', params)
        parameters.assign_context_to_process_group(self.context.fraud_pg, self.context.params.id)

        # Create controller services
        if is_tls_enabled():
            self.context.ssl_svc = nf.create_ssl_controller(self.context.root_pg)
            self.context.keytab_svc = nf.create_keytab_controller(self.context.fraud_pg)
        else:
            self.context.ssl_svc = None
            self.context.keytab_svc = None

        self.context.sr_svc = nf.create_schema_registry_controller(self.context.fraud_pg, schreg.get_api_url(),
                                                                   keytab_svc=self.context.keytab_svc,
                                                                   ssl_svc=self.context.ssl_svc)

        self.context.json_reader_svc = nf.create_json_reader_controller(
            self.context.fraud_pg,
            service_name='JsonTreeReader - Infer schema')
        self.context.json_reader_schema_svc = nf.create_json_reader_controller(
            self.context.fraud_pg, self.context.sr_svc,
            service_name='JsonTreeReader - Use schema.name',
            schema_name='${schema.name}')
        self.context.json_writer_svc = nf.create_json_writer_controller(
            self.context.fraud_pg,
            service_name='JsonRecordSetWriter - Inherit record schema')
        self.context.json_writer_schema_svc = nf.create_json_writer_controller(
            self.context.fraud_pg, self.context.sr_svc,
            service_name='JsonRecordSetWriter - Use schema.name',
            schema_write_strategy='hwx-schema-ref-attributes',
            schema_name='${schema.name}')
        self.context.rest_lookup_svc = nf.create_rest_lookup_controller(self.context.fraud_pg, '#{model.endpoint.url}',
                                                                        self.context.json_reader_schema_svc,
                                                                        record_path='/')

        # Create flow

        listen_tcp = nf.create_processor(self.context.fraud_pg, 'Receive Transactions',
                                         'org.apache.nifi.processors.standard.ListenTCP', (0, 0),
                                         {
                                             'properties': {
                                                 'Port': '#{input.port}',
                                             },
                                         })
        set_schema = nf.create_processor(self.context.fraud_pg, 'Set Schema Name',
                                         'org.apache.nifi.processors.attributes.UpdateAttribute', (0, 192),
                                         {
                                             'properties': {
                                                 'schema.name': '#{schema.name}',
                                             },
                                         })
        canvas.create_connection(listen_tcp, set_schema)

        score = nf.create_processor(self.context.fraud_pg, 'Score Transaction',
                                    'org.apache.nifi.processors.standard.LookupRecord', (0, 384),
                                    {
                                        'properties': {
                                            'record-reader': self.context.json_reader_schema_svc.id,
                                            'record-writer': self.context.json_writer_schema_svc.id,
                                            'lookup-service': self.context.rest_lookup_svc.id,
                                            'result-record-path': '/model_response',
                                            'request.body': 'concat(\'{"request":{"feature":"\', /ts, \', \', /account_id, \', \', /transaction_id, \', \', /amount, \', \', /lat, \', \', /lon, \'"}}\')',
                                            'request.method': "toString('post', 'UTF-8')",
                                            'mime.type': "toString('application/json', 'UTF-8')",
                                        },
                                    })
        canvas.create_connection(set_schema, score, name='before_lookup')

        check_score = nf.create_processor(self.context.fraud_pg, 'Check Transaction Score',
                                          'org.apache.nifi.processors.standard.QueryRecord', (0, 576),
                                          {
                                              'properties': {
                                                  'record-reader': self.context.json_reader_schema_svc.id,
                                                  'record-writer': self.context.json_writer_svc.id,
                                                  'include-zero-record-flowfiles': 'false',
                                                  'flattened': "select\n  ts,\n  account_id,\n  transaction_id,\n  amount,\n  lat,\n  lon,\n  RPATH(model_response, '/fraud_score') as fraud_score\nfrom flowfile\n",
                                                  'to_kudu': "select\n  ts,\n  account_id as acc_id,\n  transaction_id,\n  amount,\n  lat,\n  lon,\n  RPATH(model_response, '/fraud_score') as fraud_score\nfrom flowfile\n",
                                                  'likely_fraud': "select\n  ts,\n  account_id,\n  transaction_id,\n  amount,\n  lat,\n  lon,\n  RPATH(model_response, '/fraud_score') as fraud_score\nfrom flowfile\nwhere RPATH(model_response, '/fraud_score') > 0.90",
                                              },
                                              'autoTerminatedRelationships': ['original'],
                                          })
        canvas.create_connection(score, check_score, relationships=['success'], name='lookup_output')

        log_attribute = nf.create_processor(self.context.fraud_pg, 'Log Attributes',
                                            'org.apache.nifi.processors.standard.LogAttribute', (-400, 192),
                                            {
                                                'autoTerminatedRelationships': ['success'],
                                            })
        nf.create_connection(score, log_attribute, relationships=['failure'], name='failed_lookup',
                             bends=[{'x': -224.0, 'y': 448}], z_index=1)
        nf.create_connection(check_score, log_attribute, relationships=['failure'], name='failed_query',
                             bends=[{'x': -224.0, 'y': 640}], z_index=0)

        pub_fraud = nf.create_processor(self.context.fraud_pg, 'Publish to Kafka topic: frauds',
                                        'org.apache.nifi.processors.kafka.pubsub.PublishKafkaRecord_2_6', (400, 384),
                                        {
                                            'properties': {
                                                'bootstrap.servers': '#{kafka.brokers}',
                                                'topic': '#{fraud_topic}',
                                                'record-reader': self.context.json_reader_schema_svc.id,
                                                'record-writer': self.context.json_writer_schema_svc.id,
                                                'use-transactions': 'false',
                                                'acks': 'all',
                                                'security.protocol': '#{kafka.security.protocol}',
                                                'sasl.mechanism': '#{kafka.sasl.mechanism}',
                                                'sasl.username': '#{workload.user}' if is_kerberos_enabled() else None,
                                                'sasl.password': '#{workload.password}' if is_kerberos_enabled() else None,
                                                'ssl.context.service': self.context.ssl_svc.id if self.context.ssl_svc else None,
                                            },
                                            'autoTerminatedRelationships': ['success'],
                                        })
        nf.create_connection(check_score, pub_fraud, relationships=['likely_fraud'], name='likely_fraud',
                             bends=[{'x': 576.0, 'y': 640}])
        nf.create_connection(pub_fraud, pub_fraud, relationships=['failure'], name='kafka_frauds_failures',
                             bends=[{'x': 576.0, 'y': 352}, {'x': 606.0, 'y': 352}], label_index=0)

        pub_txn = nf.create_processor(self.context.fraud_pg, 'Publish to Kafka topic: transactions',
                                      'org.apache.nifi.processors.kafka.pubsub.PublishKafkaRecord_2_6', (-200, 768),
                                      {
                                          'properties': {
                                              'bootstrap.servers': '#{kafka.brokers}',
                                              'topic': '#{transaction_topic}',
                                              'record-reader': self.context.json_reader_schema_svc.id,
                                              'record-writer': self.context.json_writer_schema_svc.id,
                                              'use-transactions': 'false',
                                              'acks': 'all',
                                              'security.protocol': '#{kafka.security.protocol}',
                                              'sasl.mechanism': '#{kafka.sasl.mechanism}',
                                              'sasl.username': '#{workload.user}' if is_kerberos_enabled() else None,
                                              'sasl.password': '#{workload.password}' if is_kerberos_enabled() else None,
                                              'ssl.context.service': self.context.ssl_svc.id if self.context.ssl_svc else None,
                                          },
                                          'autoTerminatedRelationships': ['success'],
                                      })
        nf.create_connection(check_score, pub_txn, relationships=['flattened'], name='flattened',
                             bends=[{'x': 176.0, 'y': 736}, {'x': -24.0, 'y': 736}], label_index=1)
        nf.create_connection(pub_txn, pub_txn, relationships=['failure'], name='kafka_transactions_failures',
                             bends=[{'x': -24.0, 'y': 928}, {'x': 6.0, 'y': 928}], label_index=0)

        write_kudu = nf.create_processor(self.context.fraud_pg, 'Write to Kudu',
                                         'org.apache.nifi.processors.kudu.PutKudu', (200, 768),
                                         {
                                             'properties': {
                                                 'Kudu Masters': '#{kudu.master}',
                                                 'Table Name': '#{transaction_table}',
                                                 'Failure Strategy': 'route-to-failure',
                                                 'kerberos-principal': '#{workload.user}' if is_kerberos_enabled() else None,
                                                 'kerberos-password': '#{workload.password}' if is_kerberos_enabled() else None,
                                                 'record-reader': self.context.json_reader_svc.id,
                                                 'Insert Operation': 'UPSERT',
                                             },
                                             'autoTerminatedRelationships': ['success'],
                                         })
        nf.create_connection(check_score, write_kudu, relationships=['to_kudu'], name='to_kudu',
                             bends=[{'x': 176.0, 'y': 736}, {'x': 376.0, 'y': 736}], label_index=1)
        nf.create_connection(write_kudu, write_kudu, relationships=['failure'], name='kudu_failures',
                             bends=[{'x': 376.0, 'y': 928}, {'x': 406.0, 'y': 928}], label_index=0)

        # Generators
        self.context.generators_pg = canvas.create_process_group(self.context.fraud_pg, 'Generators', (800, 0))
        parameters.assign_context_to_process_group(self.context.generators_pg, self.context.params.id)

        self.context.http_ctx_map_svc = nf.create_http_context_map_controller(self.context.generators_pg)

        generate_txn = nf.create_processor(self.context.generators_pg, 'Generate Transaction Data',
                                           'org.apache.nifi.processors.script.InvokeScriptedProcessor', (0, 0),
                                           {
                                               'properties': {
                                                   'Script Engine': 'python',
                                                   'Script Body': GEN_TXN_SCRIPT,
                                                   'cities': CITIES_DEFAULT,
                                                   'fraud-freq-max': '15',
                                                   'fraud-freq-min': '5',
                                               },
                                               'schedulingPeriod': '1 sec',
                                               'schedulingStrategy': 'TIMER_DRIVEN',
                                           })

        send_txn = nf.create_processor(self.context.generators_pg, 'Send Transaction Data',
                                       'org.apache.nifi.processors.standard.PutTCP', (0, 192),
                                       {
                                           'properties': {
                                               'Hostname': '#{input.host}',
                                               'Port': '#{input.port}',
                                               'Max Size of Socket Send Buffer': '1 MB',
                                               'Idle Connection Expiration': '15 seconds',
                                               'Connection Per FlowFile': 'true',
                                               'Outgoing Message Delimiter': r'\n',
                                           },
                                           'autoTerminatedRelationships': ['success', 'failure'],
                                       })
        nf.create_connection(generate_txn, send_txn, relationships=['success'], name='txn_data')

        handle_req = nf.create_processor(self.context.generators_pg, 'Handle Scoring Request',
                                         'org.apache.nifi.processors.standard.HandleHttpRequest', (400, 0),
                                         {
                                             'properties': {
                                                 'Listening Port': '5000',
                                                 'HTTP Context Map': self.context.http_ctx_map_svc.id,
                                             },
                                         })

        replace_txt = nf.create_processor(self.context.generators_pg, 'Craft response',
                                          'org.apache.nifi.processors.standard.ReplaceText', (400, 192),
                                          {
                                              'properties': {
                                                  'Regular Expression': '(?s)(^.*$)',
                                                  'Replacement Value': '{"fraud_score": 0.${random()}}',
                                                  'Replacement Strategy': 'Regex Replace',
                                                  'Evaluation Mode': 'Entire text',
                                              },
                                          })
        nf.create_connection(handle_req, replace_txt, relationships=['success'], name='request')

        handle_resp = nf.create_processor(self.context.generators_pg, 'Handle Scoring Response',
                                          'org.apache.nifi.processors.standard.HandleHttpResponse', (400, 384),
                                          {
                                              'properties': {
                                                  'HTTP Status Code': '200',
                                                  'HTTP Context Map': self.context.http_ctx_map_svc.id,
                                              },
                                              'autoTerminatedRelationships': ['success', 'failure'],
                                          })
        nf.create_connection(replace_txt, handle_resp, relationships=['success', 'failure'], name='response')

        # Start flow
        canvas.schedule_process_group(self.context.fraud_pg.id, True)

    def lab5_create_ssb_kafka_data_provider(self):
        if is_tls_enabled():
            if is_kerberos_enabled():
                protocol = 'sasl'
            else:
                protocol = 'ssl'
        else:
            if is_kerberos_enabled():
                protocol = 'sasl_plaintext'
            else:
                protocol = 'plaintext'
        props = {
            'brokers': kafka.get_bootstrap_servers(),
            'protocol': protocol,
            'username': None,
            'password': None,
            'mechanism': 'KERBEROS',
            'ssl.truststore.location': TRUSTSTORE_PATH,
        }
        ssb.create_data_provider(KAFKA_PROVIDER_NAME, 'kafka', props)

    def lab6_create_ssb_kudu_data_provider(self):
        props = {
            'catalog_type': 'kudu',
            'kudu.masters': get_hostname() + ":7051",
            'table_filters': [{'database_filter': '.*', 'table_filter': '.*'}],
        }
        ssb.create_data_provider(KUDU_CATALOG_NAME, 'catalog', props)

    def lab7_create_ssb_tables(self):
        ssb.execute_sql(SSB_CREATE_TABLES_STMT, job_name="create_tables")

    def lab8_create_ssb_udfs(self):
        ssb.create_udf('HAVETOKM', 'Calculates Haversine distance between to geographical coordinates.',
                       ['DECIMAL', 'DECIMAL', 'DECIMAL', 'DECIMAL'], 'DECIMAL', UDF_HAVETOKM_CODE)
        ssb.create_udf('TO_KUDU_STRING', 'Convert string to Kudu format.',
                       ['STRING'], 'STRING', UDF_TO_KUDU_STRING_CODE)

    def lab9_run_ssb_job_fraud_detection_geo(self):
        ssb.execute_sql(SSB_FRAUD_JOB, job_name="fraud_detection_job")

    def lab10_create_connection(self):
        dataviz.create_connection(DATAVIZ_CONNECTION_TYPE, DATAVIZ_CONNECTION_NAME, DATAVIZ_CONNECTION_PARAMS,
                                  username='admin' if is_kerberos_enabled() else None,
                                  password=get_the_pwd() if is_kerberos_enabled() else None)

    def lab11_import_dataviz(self):
        if 'MAPBOX_TOKEN' in os.environ:
            mapbox_token = os.environ['MAPBOX_TOKEN']
        else:
            mapbox_token = ''
        source_path = os.path.join(self.get_artifacts_dir(), DATAVIZ_EXPORT_FILE)
        with tempfile.NamedTemporaryFile(mode='w') as temp_file:
            with open(source_path, 'r') as source_file:
                temp_file.write(source_file.read().replace('{{MAPBOX_TOKEN}}', mapbox_token))
                temp_file.flush()
            dataviz.import_artifacts2(DATAVIZ_CONNECTION_NAME, temp_file.name)
