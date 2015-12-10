    describe 'Modules', ->
      it 'should load', ->
        for module in ['../server','../src/dns','../src/ndns','../src/shuffle']
          require module
