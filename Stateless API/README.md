# Steps

## 1. Create the Lambda function

- Go to Lambda → Create function → Author from scratch
- Name it, choose Python 3.14, let AWS auto-create the role
- In the code editor, replace the default code with `handler.py`
- Click Deploy

## 2. Create the API

- Go to API Gateway → Create API → REST API (not private)
- Name it → Create

## 3. Create the /hello route

- Create resource `/hello` → Create method → **GET**
- Integration type: Lambda Function
- Enable **Lambda Proxy integration**
- Type your Lambda function name → Save

## 4. Create the /echo route

- Create resource `/echo` → Create method → **POST**
- Integration type: Lambda Function
- Enable **Lambda Proxy integration**
- Type your Lambda function name → Save

## 5. Deploy the API

- Actions → Deploy API → New stage → name it `dev` → Deploy
- Copy the **Invoke URL** from Stages → dev

## 6. Test it

- Send requests to the API and see the response
